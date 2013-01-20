module LdapSync::Infectors::AuthSourceLdap module ClassMethods; end

  module InstanceMethods
    public

    def sync_groups
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"; return
      end
      unless setting.sync_group_fields? || setting.create_groups?
        trace "   -> No attributes to sync: skipping"; return
      end

      with_ldap_connection do |ldap|
        groupname_pattern   = /#{setting.groupname_pattern}/

        find_all_groups(ldap, nil, [n(:groupname), *setting.group_ldap_attrs.values]) do |group_data|
          groupname = group_data[n(:groupname)].first
          next unless groupname_pattern =~ groupname

          group, is_new_group = find_or_create_group(groupname, group_data)

          trace "-- #{is_new_group ? 'Creating': 'Updating'} group '#{group.name}'..."
          sync_group_fields(group, group_data) unless is_new_group
        end
      end
    end

    def sync_users
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"
        return
      end

      @closure_cache = new_memory_cache if setting.nested_groups_enabled?

      with_ldap_connection do |_|
        ldap_users[:disabled].each do |login|
          user = ::User.where("LOWER(login) = ? AND auth_source_id = ?", login.downcase, self.id).first

          if user.try(:active?)
            user.lock!
            trace "-- Locked user '#{user.login}'"
          end
        end

        ldap_users[:enabled].each do |login|
          user, is_new_user = find_or_create_user(login)
          sync_user(user, is_new_user) if user.present?
        end
      end

      update_closure_cache! if setting.nested_groups_enabled?
    end

    def sync_user(user, is_new_user = false, attrs = {})
      with_ldap_connection(attrs[:login], attrs[:password]) do |_|
        if user.locked? && !(activate_users? || setting.has_required_group?)
          trace "-- Not #{is_new_user ? 'Creating': 'Updating'} locked user '#{user.login}'"; return
        else
          trace "-- #{is_new_user ? 'Creating': 'Updating'} user '#{user.login}'..."
        end

        sync_user_groups(user)


        return if user.locked?

        if setting.has_admin_group?
        end
        sync_admin_privilege(user)
        sync_user_fields(user) unless is_new_user
      end
    end

    private
      def find_or_create_group(groupname, group_data = nil)
        group = ::Group.where("LOWER(lastname) = ?", groupname.downcase).first
        return group unless group.nil? && setting.create_groups?

        group = ::Group.new(:lastname => groupname, :auth_source_id => self.id) do |g|
          g.set_default_values
          g.synced_fields = get_group_fields(groupname, group_data)
        end

        if group.save
          return group, true
        else
          error "Could not create group '#{groupname}': \"#{group.errors.full_messages.join('", "')}\""; nil
        end
      end

      def find_or_create_user(username)
        user = ::User.where("LOWER(login) = ?", username.downcase).first
        if user.present? && user.auth_source_id != self.id
          trace "-- Skipping user '#{user.login}': it already exists on a different auth_source"
          return nil
        end
        return user unless user.nil? && setting.create_users?

        user = ::User.new do |u|
          u.login = username
          u.set_default_values
          u.synced_fields = get_user_fields(username)
        end

        if user.save
          return user, true
        else
          trace "-- Could not create user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
        end
      end

      def sync_user_groups(user)
        return unless setting.active?

        if setting.has_fixed_group? && user.groups.none? { |g| g.to_s == setting.fixed_group }
          user.add_to_fixed_group
        end

        changes = groups_changes(user)
        user.groups << changes[:added].map {|g| find_or_create_group(g) }.compact

        deleted = Group.where("LOWER(lastname) in (?)", changes[:deleted].to_a).all
        user.groups.delete(*deleted) unless deleted.blank?

        trace groups_changes_summary(changes)
      end

      def sync_user_fields(user)
        return unless setting.active? && setting.sync_user_fields?

        user.synced_fields = get_user_fields(user.login)
        if user.save
          user
        else
          error "Could not sync user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
        end
      end

      def sync_user_status(user)
        if setting.has_required_group?
          if user.member_of_group?(setting.required_group)
            if user.locked?
              user.activate!
              trace "   -> activated: is a member of group '#{setting.required_group}'"
            end
          elsif user.active?
            user.lock!
            trace "   -> locked: is not a member of group '#{setting.required_group}'"
          end
        elsif activate_users? && user.locked?
          user.activate!
          trace "   -> activated: ACTIVATE_USERS flag is on"
        end
      end

      def sync_admin_privilege(user)
        return unless setting.has_admin_group?

        if user.member_of_group?(setting.admin_group)
          unless user.admin?
            user.set_admin!
            trace "   -> granted admin privileges: is a member of group '#{setting.admin_group}'"
          end
        else
          if user.admin?
            user.unset_admin!
            trace "   -> revoked admin privileges: is not a member of group '#{setting_group}'"
          end
        end
      end

      def sync_group_fields(group, group_data)
        group.synced_fields = get_group_fields(group.name, group_data)

        if group.save
          group
        else
          trace "-- Could not sync group '#{group.lastname}': \"#{group.errors.full_messages.join('", "')}\""; nil
        end
      end

      def get_user_fields(username)
        user_data = with_ldap_connection do |ldap|
          find_user(ldap, username, setting.user_ldap_attrs_to_sync)
        end        

        user_data.each_with_object({}) {|(a, v), h| h[setting.user_field(a)] = v.first unless a == :dn }
      end

      def get_group_fields(groupname, group_data = nil)
        group_data ||= with_ldap_connection do |ldap|
          find_group(ldap, groupname, [attrs(:groupname), *setting.group_ldap_attrs_to_sync])
        end

        group_data.each_with_object({}) {|(a, v), h| h[setting.group_field(a)] = v.first unless a == :dn }
      end

      def ldap_users
        return @ldap_users if @ldap_users

        with_ldap_connection do |ldap|
          users = { :enabled => Set.new, :disabled => Set.new }

          unless setting.has_account_flags?
            users[:enabled] += find_all_users(ldap, n(:login)).map(&:first)
          else
            find_all_users(ldap, ns(:login, :account_flags)) do |entry|
              if account_disabled?(entry[n(:account_flags)].first)
                users[:disabled] << entry[n(:login)].first
              else
                users[:enabled] << entry[n(:login)].first
              end
            end
          end
          users[:disabled] += self.users.active.collect(&:login) - users.values.sum.to_a

          trace "-- Found #{users[:disabled].length + users[:enabled].length} users"
          @ldap_users = users
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

          case setting.group_membership
          when 'on_groups'
            # Find user's memberid
            user_dn = user.login
            unless setting.user_memberid == setting.login
              user_dn = find_user(ldap, user.login, n(:user_memberid)).first
            end

            # Find the groups to which the user belongs to
            member_filter = Net::LDAP::Filter.eq( setting.member, user_dn )
            find_all_groups(ldap, member_filter, n(:groupname)) do |(group,*_)|
              changes[:added] << group if groupname_pattern =~ group
            end if user_dn

          else # 'on_members'
            groups_base_dn = setting.groups_base_dn

            groups = find_user(ldap, user.login, n(:user_groups)).select {|(g,*_)| g.end_with?(groups_base_dn)}

            names_filter = groups.map{|g| Net::LDAP::Filter.eq( setting.groupid, g )}.reduce(:|)
            find_all_groups(ldap, names_filter, n(:groupname)) do |(group,*_)|
              changes[:added] << group if groupname_pattern =~ group
            end if names_filter
          end

          changes[:added] = changes[:added].inject(Set.new) do |closure, group|
            closure + closure_cache.fetch(group) do
              get_group_closure(ldap, group).select { |g| groupname_pattern =~ g }
            end
          end if setting.nested_groups_enabled?
        end

        changes[:deleted] -= changes[:added]
        changes[:added]   -= user.groups.collect(&:lastname)

        changes
      ensure
        reset_parents_cache! unless running_rake?
        #reset_ldap_settings! unless running_rake?
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

      def find_all_groups(ldap, extra_filter, attrs, &block)
        group_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_group )
        group_filter &= Net::LDAP::Filter.construct( setting.group_search_filter ) if setting.group_search_filter.present?
        group_filter &= extra_filter if extra_filter
        groups_base_dn = setting.groups_base_dn

        ldap_search(ldap, {:base => groups_base_dn,
                     :filter => group_filter,
                     :attributes => attrs,
                     :return_result => block_given? ? false : true},
                    &block)
      end

      def find_user(ldap, login, attrs, &block)
        user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
        user_filter &= ldap_filter if filter.present?
        login_filter = Net::LDAP::Filter.eq( setting.login, login )

        result = ldap_search(ldap, {:base => self.base_dn,
                              :filter => user_filter & login_filter,
                              :attributes => attrs,
                              :return_result => block_given? ? false : true},
                             &block)
        result.first if !block_given? && result.present?
      end

      def find_all_users(ldap, attrs, &block)
        user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
        user_filter &= ldap_filter if filter.present?

        ldap_search(ldap, {:base => self.base_dn,
                     :filter => user_filter,
                     :attributes => attrs,
                     :return_result => block_given? ? false : true},
                    &block)
      end

      def ldap_search(ldap, options, &block)
        attrs = options[:attributes]

        return ldap.search(options, &block) if attrs.is_a?(Array)

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

      def new_memory_cache
        cache = Hash.new
        def cache.fetch(key, &block)
          self[key] = super(key, &block)
        end
        cache
      end

      def parents_cache
        @parents_cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
      end

      def reset_parents_cache!
        @parents_cache.clear unless @parents_cache.nil?
      end

      def cache_root
        root_path = Rails.root.join("tmp/ldap_cache/#{self.id}")
        FileUtils.mkdir_p root_path unless File.exists? root_path

        root_path
      end

      def closure_cache
        @closure_cache ||= ActiveSupport::Cache.lookup_store(:file_store, cache_root)
      end

      def update_closure_cache!
        disk_cache = ActiveSupport::Cache.lookup_store(:file_store, cache_root)
        mem_cache = @closure_cache

        # Match all the entries we want to delete
        disk_cache.delete_unless {|k| mem_cache.has_key?(k) }
        mem_cache.each {|k, v| disk_cache.write(k, v) }
      end

      def setting
        return @setting if @setting

        @setting = LdapSetting.find_by_auth_source_ldap_id(self.id)
      end

      def account_disabled?(flags)
        return false if flags.blank?
        return @account_disabled_test.call(flags) if @account_disabled_test
        return false unless setting.has_account_disabled_test?

        @account_disabled_test = eval("lambda { |flags| #{setting.account_disabled_test} }")
        @account_disabled_test.call(flags)
      end

      def pluralize(n, word)
        word.present? ? "#{n} #{word}#{'s' if n != 1}" : n.to_s
      end

      def activate_users?
        defined?($activate_users) && $activate_users
      end

      def running_rake?
        defined? $running_rake
      end

      def groups_changes_summary(groups)
        return unless running_rake?

        if groups[:added].present? || groups[:deleted].present?
          a = groups[:added].size; d = groups[:deleted].size
          msg = "   -> "
          msg << "#{pluralize(a, 'group')} added" if a > 0
          msg << " and " if a > 0 && d > 0
          msg << "#{pluralize(d, a == 0 ? 'group' : nil)} deleted" if d > 0
          msg
        end
      end

      def trace(msg = "")
        puts msg if running_rake? && !msg.nil?
      end

      def error(msg)
        if running_rake?
          puts "-- #{msg}"
        else
          logger.error msg
        end
      end

      def with_ldap_connection(login = nil, password = nil)
        thread = Thread.current

        return yield thread[:local_ldap_con] if thread[:local_ldap_con].present?

        login ||= self.account
        password ||= self.account_password
        ldap_con = initialize_ldap_con(self.account, self.account_password)
        ldap_con.open do |ldap|
          yield thread[:local_ldap_con] = ldap
        end
      end

  end

  def self.included(receiver)
    receiver.extend(ClassMethods)
    receiver.send(:include, InstanceMethods)
    receiver.class_eval do
      delegate :has_fixed_group?, :fixed_group, :to => :setting, :allow_nil => true
      unloadable
    end
  end
end