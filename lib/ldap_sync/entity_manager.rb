module LdapSync::EntityManager

  private
    def get_user_fields(username, user_data = nil)
      user_data ||= with_ldap_connection do |ldap|
        find_user(ldap, username, setting.user_ldap_attrs_to_sync)
      end

      user_data.inject({}) do |fields, (attr, value)|
        f = setting.user_field(attr)
        if User::STANDARD_FIELDS.include?(f) || setting.user_fields_to_sync.include?(f)
          fields[f] = value.first unless f.nil?
        end
        fields
      end
    end

    def get_group_fields(groupname, group_data = nil)
      group_data ||= with_ldap_connection do |ldap|
        find_group(ldap, groupname, [n(:groupname), *setting.group_ldap_attrs_to_sync])
      end || {}

      group_data.inject({}) do |fields, (attr, value)|
        f = setting.group_field(attr)
        if setting.group_fields_to_sync.include? f
          fields[f] = value.first unless f.nil?
        end
        fields
      end
    end

    def ldap_users
      return @ldap_users if @ldap_users

      with_ldap_connection do |ldap|
        changes = { :enabled => Set.new, :disabled => Set.new }

        unless setting.has_account_flags?
          changes[:enabled] += find_all_users(ldap, n(:login)).map(&:first)
        else
          find_all_users(ldap, ns(:login, :account_flags)) do |entry|
            if account_disabled?(entry[n(:account_flags)].first)
              changes[:disabled] << entry[n(:login)].first
            else
              changes[:enabled] << entry[n(:login)].first
            end
          end
        end

        users_on_local = self.users.active.map {|u| u.login.downcase }
        users_on_ldap = changes.values.sum.map(&:downcase)
        deleted_users = users_on_local - users_on_ldap
        changes[:disabled] += deleted_users

        msg = "-- Found #{changes[:enabled].size} users active"
        msg += ", #{changes[:disabled].size - deleted_users.size} locked"
        msg += " and #{deleted_users.size} deleted on ldap"
        trace msg

        @ldap_users = changes
      end

    end

    def groups_changes(user)
      return unless setting.active?
      changes = { :added => Set.new, :deleted => Set.new }

      with_ldap_connection do |ldap|
        groupname_pattern   = /#{setting.groupname_pattern}/

        # Find which of the user's current groups are in ldap
        user_groups   = user.groups.select {|g| groupname_pattern =~ g.to_s}
        names_filter  = user_groups.map {|g| Net::LDAP::Filter.eq( setting.groupname, g.to_s )}.reduce(:|)
        find_all_groups(ldap, names_filter, n(:groupname)) do |group|
          changes[:deleted] << group.first
        end if names_filter

        user_dn = nil
        case setting.group_membership
        when 'on_groups'
          # Find user's memberid
          memberid = user.login
          if setting.user_memberid != setting.login
            entry = find_user(ldap, user.login, ns(:user_memberid))
            memberid = entry[n(:user_memberid)].first
            user_dn = entry[:dn].first
          end

          # Find the groups to which the user belongs to
          member_filter = Net::LDAP::Filter.eq( setting.member, memberid )
          find_all_groups(ldap, member_filter, n(:groupname)) do |group|
            changes[:added] << group.first
          end if memberid

        else # 'on_members'
          entry = find_user(ldap, user.login, ns(:user_groups))
          groups = entry[n(:user_groups)]
          user_dn = entry[:dn].first

          names_filter = groups.map{|g| Net::LDAP::Filter.eq( setting.groupid, g )}.reduce(:|)
          find_all_groups(ldap, names_filter, n(:groupname)) do |group|
            changes[:added] << group.first
          end if names_filter
        end

        changes[:added] = changes[:added].inject(Set.new) do |closure, group|
          closure + closure_cache.fetch(group) do
            get_group_closure(ldap, group).select {|g| groupname_pattern =~ g }
          end
        end if setting.nested_groups_enabled?

        if setting.sync_dyngroups?
          user_dn ||= find_user(ldap, user.login, :dn).first
          changes[:added] += get_dynamic_groups(user_dn)
        end

        changes[:added].delete_if {|group| groupname_pattern !~ group }
      end

      changes[:deleted] -= changes[:added]
      user_groups = user.groups.map {|g| g.lastname.downcase }
      changes[:added].delete_if {|group| user_groups.include?(group.downcase) }

      changes
    ensure
      reset_parents_cache! unless running_rake?
    end

    def get_dynamic_groups(user_dn)
      reload_dyngroups! unless dyngroups_fresh?

      dyngroups_cache.fetch(member_key(user_dn)) || []
    end

    def reload_dyngroups!
      with_ldap_connection {|c| find_all_dyngroups(c, :update_cache => true) }
    end

    def get_group_closure(ldap, group, closure=Set.new)
      groupname = group.is_a?(String) ? group : group[n(:groupname)].first
      parent_groups = parents_cache.fetch(groupname) do
        case setting.nested_groups
        when 'on_members'
          group = find_group(ldap, groupname, ns(:groupname, :group_memberid, :parent_group)) if group.is_a? String

          if group[n(:parent_group)].present?
            groups_filter = group[n(:parent_group)].map{|g| Net::LDAP::Filter.eq( setting.group_parentid, g )}.reduce(:|)
            find_all_groups(ldap, groups_filter, ns(:groupname, :group_memberid, :parent_group))
          else
            Array.new
          end
        else # 'on_parents'
          group = find_group(ldap, groupname, ns(:groupname, :group_memberid)) if group.is_a? String

          member_filter = Net::LDAP::Filter.eq( setting.member_group, group[n(:group_memberid)].first )
          find_all_groups(ldap, member_filter, ns(:groupname, :group_memberid))
        end
      end

      closure << groupname
      parent_groups.each_with_object(closure) do |group, closure|
        closure += get_group_closure(ldap, group, closure) unless closure.include? group[n(:groupname)].first
      end
    end

    def find_group(ldap, group_name, attrs, &block)
      extra_filter = Net::LDAP::Filter.eq( setting.groupname, group_name )
      result = find_all_groups(ldap, extra_filter, attrs, &block)
      result.first if !block_given? && result.present?
    end

    def find_all_groups(ldap, extra_filter, attrs, options = {}, &block)
      object_class = options[:class] || setting.class_group
      group_filter = Net::LDAP::Filter.eq( :objectclass, object_class )
      group_filter &= Net::LDAP::Filter.construct( setting.group_search_filter ) if setting.group_search_filter.present?
      group_filter &= extra_filter if extra_filter

      ldap_search(ldap, {:base => setting.groups_base_dn,
                   :filter => group_filter,
                   :attributes => attrs,
                   :return_result => block_given? ? false : true},
                  &block)
    end

    def find_all_dyngroups(ldap, options = {})
      options = options.reverse_merge(:attrs => [:cn, :member], :update_cache => false)
      users_base_dn = setting.base_dn.downcase

      dyngroups = Hash.new{|h,k| h[k] = []}

      find_all_groups(ldap, nil, options[:attrs], :class => 'groupOfURLs') do |entry|
        yield entry if block_given?

        if options[:update_cache]
          entry[:member].each do |member|
            next unless (member.downcase.ends_with?(users_base_dn))

            dyngroups[member_key(member)] << entry[:cn].first
          end
        end
      end

      update_dyngroups_cache!(dyngroups) if options[:update_cache]
    end

    def find_user(ldap, login, attrs, &block)
      user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
      user_filter &= setting.ldap_filter if setting.filter.present?
      login_filter = Net::LDAP::Filter.eq( setting.login, login )

      result = ldap_search(ldap, {:base => setting.base_dn,
                            :filter => user_filter & login_filter,
                            :attributes => attrs,
                            :return_result => block_given? ? false : true},
                           &block)
      result.first if !block_given? && result.present?
    end

    def find_all_users(ldap, attrs, &block)
      user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
      user_filter &= setting.ldap_filter if setting.filter.present?

      ldap_search(ldap, {:base => setting.base_dn,
                   :filter => user_filter,
                   :attributes => attrs,
                   :return_result => block_given? ? false : true},
                  &block)
    end

    def ldap_search(ldap, options, &block)
      attrs = options[:attributes]

      return ldap.search(options, &block) if attrs.is_a?(Array) || attrs.nil?

      options[:attributes] = [attrs]

      block = Proc.new {|e| yield e[attrs] } if block_given?
      result = ldap.search(options, &block)
      result.map {|e| e[attrs] } unless block_given? || result.nil?
    end

    def n(field)
      setting.send(field)
    end

    def ns(*args)
      setting.ldap_attributes(*args)
    end

    def member_key(member)
      member[0...-setting.base_dn.length-1]
    end

    def account_disabled?(flags)
      return false if flags.blank?
      return @account_disabled_test.call(flags) if @account_disabled_test
      return false unless setting.has_account_disabled_test?

      @account_disabled_test = eval("lambda { |flags| #{setting.account_disabled_test} }")
      @account_disabled_test.call(flags)
    end

    def connect_as_user?; setting.account.include?('$login'); end

    def with_ldap_connection(login = nil, password = nil)
      thread = Thread.current

      return yield thread[:local_ldap_con] if thread[:local_ldap_con].present?

      ldap_con = if setting.account && setting.account.include?('$login')
        initialize_ldap_con(setting.account.sub('$login', Net::LDAP::DN.escape(login)), password)
      else
        initialize_ldap_con(setting.account, setting.account_password)
      end

      ldap_con.open do |ldap|
        begin
          yield thread[:local_ldap_con] = ldap
        ensure
          thread[:local_ldap_con] = nil
        end
      end
    end
end