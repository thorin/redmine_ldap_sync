module LdapSync::Infectors::AuthSourceLdap

  module InstanceMethods
    public

    def sync_groups
      if connect_as_user?
        trace "   -> Cannot synchronize: no account/password configured"; return
      end
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"; return
      end
      unless setting.sync_group_fields? || setting.create_groups? || setting.sync_dyngroups?
        trace "   -> No attributes to sync: skipping"; return
      end

      with_ldap_connection do |ldap|
        groupname_pattern  = /#{setting.groupname_pattern}/

        trace "** Synchronizing non-dynamic groups"
        attrs = [n(:groupname), *setting.group_ldap_attrs_to_sync]
        find_all_groups(ldap, nil, attrs) do |entry|
          create_and_sync_group(entry, n(:groupname))
        end if setting.sync_group_fields? || setting.create_groups?

        return unless setting.sync_dyngroups?

        trace "** Synchronizing dynamic groups"
        find_all_dyngroups(ldap,
          :attrs => [:cn, :member, *setting.group_ldap_attrs_to_sync],
          :update_cache => !dyngroups_fresh?) do |entry|
          create_and_sync_group(entry, :cn)
        end
      end
    end

    def sync_users
      if connect_as_user?
        trace "   -> Cannot synchronize: no account/password configured"; return
      end
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"; return
      end

      @closure_cache = new_memory_cache if setting.nested_groups_enabled?

      with_ldap_connection do |_|
        ldap_users[:disabled].each do |login|
          user = ::User.where("LOWER(login) = ? AND auth_source_id = ?", login.downcase, self.id).first

          if user.try(:active?)
            if user.lock!
              trace "-- Locked active user '#{user.login}'"
            else
              trace "-- Failed to lock active user '#{user.login}'"
            end
          elsif user.present?
            trace "-- Not locking locked user '#{user.login}'"
          end
        end

        ldap_users[:enabled].each do |login|
          user, is_new_user = find_or_create_user(login)
          sync_user(user, is_new_user) if user.present?
        end
      end

      update_closure_cache! if setting.nested_groups_enabled?
    end

    def sync_user(user, is_new_user = false, options = {})
      with_ldap_connection(options[:login], options[:password]) do |ldap|
        if user.locked? && !(activate_users? || setting.has_required_group?)
          trace "-- Not #{is_new_user ? 'creating': 'updating'} locked user '#{user.login}'"; return
        else
          trace "-- #{is_new_user ? 'Creating': 'Updating'} user '#{user.login}'..."
        end

        user_data, flags = if options[:try_to_login] && setting.has_account_flags? && setting.sync_fields_on_login?
          user_data = find_user(ldap, user.login, setting.user_ldap_attrs_to_sync + ns(:account_flags))
          [user_data, user_data[n(:account_flags)].first]
        end

        sync_user_groups(user) unless options[:try_to_login] && !setting.sync_groups_on_login?
        sync_user_status(user, flags)

        return if user.locked?

        sync_admin_privilege(user)
        sync_user_fields(user, user_data) unless is_new_user || (options[:try_to_login] && !setting.sync_fields_on_login?)
      end
    end

    private
      def create_and_sync_group(group_data, attr_groupname)
        groupname = group_data[attr_groupname].first
        return unless /#{setting.groupname_pattern}/ =~ groupname

        group, is_new_group = find_or_create_group(groupname, group_data)
        return if group.nil?

        trace "-- #{is_new_group ? 'Creating': 'Updating'} group '#{group.name}'..."
        sync_group_fields(group, group_data) unless is_new_group

        group
      end

      def sync_user_groups(user)
        return unless setting.active?

        if setting.has_fixed_group? && user.groups.none? { |g| g.to_s == setting.fixed_group }
          user.add_to_fixed_group
        end

        changes = groups_changes(user)
        added = changes[:added].map {|g| find_or_create_group(g).first }.compact
        user.groups << added if added.present?

        deleted = ::Group.where("LOWER(lastname) in (?)", changes[:deleted].map(&:downcase)).all
        user.groups.delete(*deleted) if deleted.present?

        trace groups_changes_summary(changes, added, deleted)
      end

      def sync_user_fields(user, user_data = nil)
        return unless setting.active? && setting.sync_user_fields?

        user.synced_fields = get_user_fields(user.login, user_data)
        if user.save
          user
        else
          error "Could not sync user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
        end
      end

      def sync_user_status(user, flags = nil)
        if flags && account_disabled?(flags)
          user.lock!
          trace "   -> locked: user disabled on ldap with flags '#{flags}'"
        elsif setting.has_required_group?
          if user.member_of_group?(setting.required_group)
            if user.locked?
              user.activate!
              trace "   -> activated: member of group '#{setting.required_group}'"
            end
          elsif user.active?
            user.lock!
            trace "   -> locked: not member of group '#{setting.required_group}'"
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
            trace "   -> granted admin privileges: member of group '#{setting.admin_group}'"
          end
        else
          if user.admin?
            user.unset_admin!
            trace "   -> revoked admin privileges: not member of group '#{setting.admin_group}'"
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

      def get_user_fields(username, user_data = nil)
        user_data ||= with_ldap_connection do |ldap|
          find_user(ldap, username, setting.user_ldap_attrs_to_sync)
        end

        user_data.inject({}) do |fields, (attr, value)|
          f = setting.user_field(attr)
          fields[f] = value.first unless f.nil?
          fields
        end
      end

      def get_group_fields(groupname, group_data = nil)
        group_data ||= with_ldap_connection do |ldap|
          find_group(ldap, groupname, [n(:groupname), *setting.group_ldap_attrs_to_sync])
        end || {}

        group_data.inject({}) do |fields, (attr, value)|
          f = setting.group_field(attr)
          fields[f] = value.first unless f.nil?
          fields
        end
      end

      def find_or_create_group(groupname, group_data = nil)
        group = ::Group.where("LOWER(lastname) = ?", groupname.downcase).first
        return group, false unless group.nil? && setting.create_groups?

        group = ::Group.new(:lastname => groupname, :auth_source_id => self.id) do |g|
          g.set_default_values
          g.synced_fields = get_group_fields(groupname, group_data)
        end

        if group.save
          return group, true
        else
          error "Could not create group '#{groupname}': \"#{group.errors.full_messages.join('", "')}\""
          return nil, false
        end
      end

      def find_or_create_user(username)
        user = ::User.where("LOWER(login) = ?", username.downcase).first
        if user.present? && user.auth_source_id != self.id
          trace "-- Skipping user '#{user.login}': it already exists on a different auth_source"
          return nil, false
        end
        return user unless user.nil? && setting.create_users?

        user = ::User.new do |u|
          u.login = username
          u.set_default_values
          u.synced_fields = get_user_fields(username)
          u.auth_source_id = self.id
        end

        if user.save
          return user, true
        else
          trace "-- Could not create user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
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
        groups_base_dn = setting.groups_base_dn

        ldap_search(ldap, {:base => groups_base_dn,
                     :filter => group_filter,
                     :attributes => attrs,
                     :return_result => block_given? ? false : true},
                    &block)
      end

      def find_all_dyngroups(ldap, options = {})
        options = options.reverse_merge(:attrs => [:cn, :member], :update_cache => false)
        users_base_dn = self.base_dn.downcase

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

      def member_key(member)
        member[0...-self.base_dn.length-1]
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

      def reload_dyngroups!
        with_ldap_connection {|c| find_all_dyngroups(c, :update_cache => true) }
      end

      def dyngroups_fresh?
        if running_rake?
          !dyngroups_updated?
        else
          opts = {}
          if setting.dyngroups_enabled_with_ttl?
            # We do a TTL bump here to reduce the load on LDAP
            opts[:race_condition_ttl] = 5.minutes
            opts[:expires_in] = setting.dyngroups_cache_ttl.to_f.minutes
          end

          expired = false
          dyngroups_cache.fetch(:cache_control, opts) { expired = true }
          !expired
        end
      end

      def closure_cache
        @closure_cache ||= ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/nested_groups")
      end

      def dyngroups_cache
        @dyngroups_cache ||= ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/dyngroups")
      end

      def update_closure_cache!
        disk_cache = ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/nested_groups")
        mem_cache = @closure_cache

        # Match all the entries we want to delete
        disk_cache.delete_unless {|k| mem_cache.has_key?(k) }
        mem_cache.each {|k, v| disk_cache.write(k, v) }
      end

      def update_dyngroups_cache!(mem_cache)
        opts = {}
        if setting.dyngroups_enabled_with_ttl?
          opts[:race_condition_ttl] = 5.minutes
          opts[:expires_in] = setting.dyngroups_cache_ttl.to_f.minutes
        end
        dyngroups_cache.write(:cache_control, true, opts)

        dyngroups_cache.delete_unless {|k| k == 'cache_control' || mem_cache.has_key?(k) }
        mem_cache.each {|k, v| dyngroups_cache.write(k, v) }

        self.dyngroups_updated = true
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

      def groups_changes_summary(groups, added, deleted)
        return unless running_rake?

        a = added.size; d = deleted.size; nc = groups[:added].size - a
        chg = []
        chg << "#{pluralize(a, 'group')} added" if a > 0
        chg << "#{pluralize(d, a == 0 ? 'group' : nil)} deleted" if d > 0
        chg << "#{pluralize(nc, a + d == 0 ? 'group' : nil)} not created" if nc > 0

        if chg.size == 1
          "   -> #{chg[0]}"
        elsif chg.size > 1
          "   -> #{[chg[0...-1].join(', '), chg[-1]].join(' and ')}"
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

        ldap_con = if self.account && self.account.include?('$login')
          initialize_ldap_con(self.account.sub('$login', Net::LDAP::DN.escape(login)), password)
        else
          initialize_ldap_con(self.account, self.account_password)
        end

        ldap_con.open do |ldap|
          begin
            yield thread[:local_ldap_con] = ldap
          ensure
            thread[:local_ldap_con] = nil
          end
        end
      end

      def dyngroups_updated?; self.dyngroups_updated; end
      def connect_as_user?; self.account.include?('$login'); end
      def activate_users?; self.activate_users; end
      def running_rake?; self.running_rake; end
  end

  module ClassMethods
    def activate_users!
      self.activate_users = true
    end

    def running_rake!
      self.running_rake = true
    end
  end

  def self.included(receiver)
    receiver.extend(ClassMethods)
    receiver.send(:include, InstanceMethods)

    receiver.instance_eval do
      delegate :has_fixed_group?, :fixed_group, :sync_on_login?, :to => :setting, :allow_nil => true
      cattr_accessor :activate_users, :running_rake, :dyngroups_updated
      unloadable
    end
  end
end