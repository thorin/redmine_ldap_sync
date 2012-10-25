module RedmineLdapSync
  module RedmineExt
    module AuthSourceLdapPatch
      def self.included(base)
        base.class_eval do

          public
          def sync_groups(user)
            return unless ldapsync_active?

            if fixed_group.present? && user.groups.none? { |g| g.to_s == fixed_group }
              user.add_to_fixed_group
            end

            changes = groups_changes(user)
            user.groups << changes[:added].map do |groupname|
              if create_groups?
                group = Group.find_or_create_by_lastname(groupname, :auth_source_id => self.id)
                if group.valid?
                  group
                else
                  logger.error "Could not create group '#{groupname}': \"#{group.errors.full_messages.join('", "')}\""; nil
                end
              else
                Group.find_by_lastname(groupname)
              end
            end.compact

            deleted = Group.find_all_by_lastname(changes[:deleted])
            user.groups.delete(*deleted) unless deleted.nil?

            changes
          end

          def sync_users
            return unless ldapsync_active?

            @syncing_users = true
            @closure_cache = new_memory_cache if nested_groups_enabled?

            ldap_users[:disabled].each do |login|
              user = User.find_by_login_and_auth_source_id(login, self.id)

              if user.present? && user.active?
                user.lock!
                puts "-- Locked user '#{user.login}'"
              end
            end

            required_group = settings[:required_group]

            ldap_users[:enabled].each do |login|
              user_is_fresh = false
              user = User.find_by_login(login)

              user = User.create(get_user_dn(login, '').except(:dn)) do |u|
                u.login = login
                u.language = Setting.default_language
                user_is_fresh = true
              end if user.nil? && create_users?

              next if user.nil?
              if user.auth_source_id != self.id
                puts "-- Skipping user '#{user.login}': it already exists on a different auth_source"
                next
              end
              if !user.valid?
                puts "-- Could not create user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""
                next
              end

              puts "-- Creating user '#{user.login}'..." if user_is_fresh
              puts "-- Updating user '#{user.login}'..." if !user_is_fresh

              groups = sync_groups(user)
              if groups[:added].present? || groups[:deleted].present?
                a = groups[:added].size; d = groups[:deleted].size
                print "   -> "
                print "#{pluralize(a, 'group')} added" if a > 0
                print " and " if a > 0 && d > 0
                print "#{pluralize(d, a == 0 ? 'group' : nil)} deleted" if d > 0
                puts
              end

              sync_user_attributes(user) unless user_is_fresh

              if user.groups.exists?(:lastname => required_group)
                if user.locked?
                  user.activate!
                  puts "   -> activated: the user is a member of group '#{required_group}'"
                end
              elsif user.active?
                user.lock!
                puts "   -> locked: the user is not a member of group '#{required_group}'"
              end if required_group.present?
            end

            update_closure_cache! if nested_groups_enabled?
          end

          def sync_user_attributes(user)
            return unless sync_user_attributes?

            attrs = get_user_dn(user.login, '')
            user.update_attributes(attrs.slice(*settings[:attributes_to_sync].map(&:intern)))
          end

          def lock_unless_member_of(user)
            required_group = settings && settings[:required_group]
            user.lock! if required_group.present? && !user.groups.exists?(:lastname => required_group)
          end

          def fixed_group
            settings[:fixed_group]
          end

          def ldapsync_active?
            settings && settings[:active]
          end

          protected
          def ldap_users
            return @ldap_users if @ldap_users

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            users = {:enabled => [], :disabled => []}

            if settings[:account_flags].blank?
              users[:enabled] = find_all_users(ldap_con, [:login])
            else
              find_all_users(ldap_con, [:login, :account_flags]) do |entry|
                if account_disabled?(entry[:account_flags])
                  users[:disabled] << entry[:login]
                else
                  users[:enabled] << entry[:login]
                end
              end
            end

            users[:disabled] += self.users.active.collect(&:login) - users.values.flatten

            @ldap_users = users
          end

          def groups_changes(user)
            return unless ldapsync_active?
            changes = { :added => [], :deleted => [] }

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            ldap_con.open do |ldap|
              groupname_pattern   = /#{settings[:groupname_pattern]}/

              # Find which of the user's current groups are in ldap
              user_groups   = user.groups.select {|g| groupname_pattern =~ g.to_s}
              names_filter  = user_groups.map {|g| Net::LDAP::Filter.eq( settings[:groupname], g.to_s )}.reduce(:|)
              find_all_groups(ldap, names_filter, [:groupname]) do |group|
                changes[:deleted] << group
              end if names_filter

              case settings[:group_membership]
              when 'on_groups'
                # Find user's memberid
                user_dn = user.login
                unless settings[:user_memberid] == settings[:login]
                  user_dn = find_user(ldap, user.login, [:user_memberid])
                end

                # Find the groups to which the user belongs to
                member_filter = Net::LDAP::Filter.eq( settings[:member], user_dn )
                find_all_groups(ldap, member_filter, [:groupname]) do |group|
                  changes[:added] << group if groupname_pattern =~ group
                end if user_dn

              else # 'on_members'
                groups_base_dn = settings[:groups_base_dn]

                groups = find_user(ldap, user.login, [:user_groups]).select {|g| g.end_with?(groups_base_dn)}

                names_filter = groups.map{|g| Net::LDAP::Filter.eq( settings[:groupid], g )}.reduce(:|)
                find_all_groups(ldap, names_filter, [:groupname]) do |group|
                  changes[:added] << group if groupname_pattern =~ group
                end if names_filter
              end

              changes[:added] = changes[:added].inject(Set.new) do |closure, group|
                closure + closure_cache.fetch(group) do
                  get_group_closure(ldap, group).select { |g| groupname_pattern =~ g }
                end
              end.to_a if nested_groups_enabled?
            end

            changes[:deleted] -= changes[:added]
            changes[:added]   -= user.groups.collect(&:lastname)

            changes
          ensure
            reset_parents_cache! unless syncing_users?
            reset_ldap_settings! unless syncing_users?
          end

          def get_group_closure(ldap, group, closure=Set.new)
            groupname = group[:groupname] || group
            parent_groups = parents_cache.fetch(groupname) do
              case settings[:nested_groups]
              when 'on_members'
                group = find_group(ldap, groupname, [:groupname, :group_memberid, :parent_group]) unless group.is_a? Hash

                if group[:parent_group].present?
                  groups_filter = group[:parent_group].map{|g| Net::LDAP::Filter.eq( settings[:group_parentid], g )}.reduce(:|)
                  find_all_groups(ldap, groups_filter, [:groupname, :group_memberid, :parent_group])
                else
                  Array.new
                end
              else # 'on_parents'
                group = find_group(ldap, groupname, [:groupname, :group_memberid]) unless group.is_a? Hash

                member_filter = Net::LDAP::Filter.eq( settings[:member_group], group[:group_memberid] )
                find_all_groups(ldap, member_filter, [:groupname, :group_memberid])
              end
            end

            closure << groupname
            parent_groups.inject(closure) do |closure, group|
              closure += get_group_closure(ldap, group, closure) unless closure.include? group[:groupname]
              closure
            end
          end

          def find_group(ldap, group_name, attrs, &block)
            extra_filter = Net::LDAP::Filter.eq( settings[:groupname], group_name )
            result = find_all_groups(ldap, extra_filter, attrs, &block)
            result.first if !block_given? && result.present?
          end

          def find_all_groups(ldap, extra_filter, attrs, &block)
            group_filter = Net::LDAP::Filter.eq( :objectclass, settings[:class_group] )
            group_filter &= Net::LDAP::Filter.construct( settings[:group_search_filter] ) if settings[:group_search_filter].present?
            groups_base_dn = settings[:groups_base_dn]

            ldap_search(ldap, {:base => groups_base_dn,
                         :filter => group_filter & extra_filter,
                         :attributes => attrs,
                         :return_result => block_given? ? false : true},
                        &block)
          end

          def find_user(ldap, login, attrs, &block)
            user_filter = Net::LDAP::Filter.eq( :objectclass, settings[:class_user] )
            login_filter = Net::LDAP::Filter.eq( settings[:login], login )

            result = ldap_search(ldap, {:base => self.base_dn,
                                  :filter => user_filter & login_filter,
                                  :attributes => attrs,
                                  :return_result => block_given? ? false : true},
                                 &block)
            result.first if !block_given? && result.present?
          end

          def find_all_users(ldap, attrs, &block)
            user_filter = Net::LDAP::Filter.eq( :objectclass, settings[:class_user] )

            ldap_search(ldap, {:base => self.base_dn,
                         :filter => user_filter,
                         :attributes => attrs,
                         :return_result => block_given? ? false : true},
                        &block)
          end

          def ldap_search(ldap, options, &block)
            options[:attributes].map! {|n| attribute_of(n) } if options[:attributes]
            attrs = options[:attributes]

            block = Proc.new { |e| yield renamed_attrs(e, attrs); } if block_given?
            result = ldap.search(options, &block)
            result.map { |e| renamed_attrs(e, attrs) } unless block_given? || result.nil?
          end

          def renamed_attrs(ldap_entry, attrs)
            multivalued_attrs = [ attribute_of(:user_groups), attribute_of(:parent_group) ]

            if attrs.length == 1
              value = ldap_entry[attrs.first]
              multivalued_attrs.include?(attrs.first) ? value : value.first
            else
              entry = Hash.new
              ldap_entry.each do |k, v|
                value = (multivalued_attrs.include?(k) ? v : v.first)
                name_of(k).each {|n| entry[n] = value }
              end
              entry
            end
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

          def syncing_users?
            @syncing_users
          end

          def sync_user_attributes?
            ldapsync_active? && settings[:sync_user_attributes]
          end

          def create_groups?
            settings && settings[:create_groups]
          end

          def create_users?
            settings && settings[:create_users]
          end

          def nested_groups_enabled?
            settings && settings[:nested_groups].present?
          end

          def account_disabled?(flags)
            return false if flags.blank?
            return @account_disabled_test.call(flags) if @account_disabled_test
            return false if settings[:account_disabled_test].blank?

            @account_disabled_test = eval("lambda { |flags| #{settings[:account_disabled_test]} }")
            @account_disabled_test.call(flags)
          end

          def pluralize(n, word)
            word.present? ? "#{n} #{word}#{'s' if n != 1}" : n.to_s
          end

          def settings
            return @settings if @settings

            @settings = Setting.plugin_redmine_ldap_sync.fetch(self.name, Hash.new)
            @settings[:login] = self.attr_login
            @settings[:object_class] = 'objectClass'
            @settings.slice(*@@LDAP_ATTRIBUTES).each do |key, value|
              @settings[key] = (value.to_s.downcase.to_sym if value.present?)
            end

            @settings
          end

          def attribute_of(name)
            settings[name]
          end

          @@LDAP_ATTRIBUTES = [:object_class, :login, :groupname, :member, :user_memberid,
                               :user_groups, :groupid, :member_group, :group_memberid,
                               :parent_group, :group_parentid, :account_flags]
          def name_of(attribute)
            return @attribute_names[attribute] if @attribute_names

            @attribute_names = Hash.new(Array.new)
            settings.slice(*@@LDAP_ATTRIBUTES).each do |name, attrb|
              if @attribute_names.has_key? attrb
                @attribute_names[attrb] << name.to_sym
              else
                @attribute_names[attrb] = [ name.to_sym ]
              end
            end

            @attribute_names[attribute]
          end

          def reset_ldap_settings!
            @settings = nil
            @attribute_names = nil
          end

          # Adds compatibility with versions prior to rev. 9241
          if instance_method(:get_user_dn).arity == 1
            def get_user_dn_with_ldap_sync(login, password = '')
              get_user_dn_without_ldap_sync(login)
            end

            alias_method_chain :get_user_dn, :ldap_sync
          end

        end

      end
    end
  end
end
