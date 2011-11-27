module RedmineLdapSync
  module RedmineExt
    module AuthSourceLdapPatch
      def self.included(base)
        base.class_eval do

          public
          def sync_groups(user)
            return unless ldapsync_active?

            if add_to_group && !user.groups.detect { |g| g.to_s == add_to_group }
              user.add_to_auth_source_group
            end

            changes = groups_changes(user)
            changes[:added].each do |groupname|
              group = if create_groups?
                Group.find_or_create_by_lastname(groupname, :auth_source_id => self.id)
              else
                Group.find_by_lastname(groupname)
              end

              group.users << user if group
            end

            changes[:deleted].each do |groupname|
              next unless group = user.groups.detect { |g| g.to_s == groupname }

              group.users.delete(user)
            end

            changes
          end

          def sync_users
            return unless ldapsync_active?

            ldap_users[:disabled].each do |login|
              user = User.find_by_login_and_auth_source_id(login, self.id)

              if user.present? && user.active?
                user.lock!
                puts "-- Locked user '#{user.login}'"
              end
            end

            groupname = settings[:must_be_member_of]

            ldap_users[:enabled].each do |login|
              user_is_fresh = false
              user = User.find_by_login(login)
              user = User.create do |u|
                u.login = login
                u.attributes = get_user_dn(login).except(:dn)
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

              if user.groups.exists?(:lastname => groupname)
                if user.locked?
                  user.activate!
                  puts "   -> activated: the user is a member of group '#{groupname}'"
                end
              elsif user.active?
                user.lock!
                puts "   -> locked: the user is not a member of group '#{groupname}'"
              end if groupname.present?
            end
          end

          def sync_user_attributes(user)
            return unless sync_user_attributes?

            attrs = get_user_dn(user.login)
            user.update_attributes(attrs.slice(*settings[:attributes_to_sync].map(&:intern)))
          end

          def lock_unless_member_of(user)
            groupname = settings && settings[:must_be_member_of]
            user.lock! if groupname.present? && !user.groups.exists?(:lastname => groupname)
          end

          def add_to_group
            settings[:add_to_group]
          end

          protected
          def ldap_users
            return @ldap_users if @ldap_users

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            user_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_user] )
            attr_enabled = 'userAccountControl'
            users = {:enabled => [], :disabled => []}

            ldap_con.search(:base => self.base_dn,
                            :filter => user_filter,
                            :attributes => [self.attr_login, attr_enabled],
                            :return_result => false) do |entry|
              if entry[attr_enabled] && entry[attr_enabled][0].to_i & 2 != 0
                users[:disabled] << entry[self.attr_login][0]
              else
                users[:enabled] << entry[self.attr_login][0]
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
              attr_groupname      = settings[:attr_groupname]

              # Find which of the user's current groups are in ldap
              user_groups   = user.groups.select {|g| groupname_pattern =~ g.to_s}
              names_filter  = user_groups.map {|g| Net::LDAP::Filter.eq( attr_groupname, g.to_s )}.reduce(:|)
              find_all_groups(ldap, names_filter, [ attr_groupname ]) do |entry|
                changes[:deleted] << entry[attr_groupname][0]
              end if names_filter

              case settings[:group_membership]
              when 'on_groups'
                attr_member         = settings[:attr_member]
                attr_user_memberid  = settings[:attr_user_memberid]

                # Find user's memberid
                user_dn = user.login
                find_user(ldap, user.login, [attr_user_memberid]) do |entry|
                  user_dn = entry[attr_user_memberid][0]
                end unless attr_user_memberid == self.attr_login

                # Find the groups which the user belongs to
                member_filter = Net::LDAP::Filter.eq( attr_member, user_dn )
                find_all_groups(ldap, member_filter, [attr_groupname]) do |entry|
                  group = entry[attr_groupname][0]
                  changes[:added] << group if groupname_pattern =~ group
                end if user_dn

              else # 'on_members'
                groups_base_dn    = settings[:groups_base_dn]
                attr_user_groups  = settings[:attr_user_groups]
                attr_groupid      = settings[:attr_groupid]

                groups  = []
                find_user(ldap, user.login, [attr_user_groups]) do |entry|
                  groups = entry[attr_user_groups].select {|g| g.end_with?(groups_base_dn)}
                end

                names_filter = groups.map{|g| Net::LDAP::Filter.eq( attr_groupid, g )}.reduce(:|)
                find_all_groups(ldap, names_filter, [attr_groupname]) do |entry|
                  group = entry[attr_groupname][0]
                  changes[:added] << group if groupname_pattern =~ group
                end if names_filter
              end
            end

            changes[:deleted] -= changes[:added]
            changes[:added]   -= user.groups.collect(&:lastname)

            changes
          end

          def find_all_groups(ldap, extra_filter, attrs, &block)
            group_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_group] )
            group_filter &= Net::LDAP::Filter.construct( settings[:group_search_filter] ) if settings[:group_search_filter].present?
            groups_base_dn = settings[:groups_base_dn]

            ldap.search(:base => groups_base_dn,
                        :filter => group_filter & extra_filter,
                        :attributes => attrs,
                        :return_result => false) do |entry|
              yield entry
            end
          end

          def find_user(ldap, login, attrs, &block)
            user_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_user] )
            login_filter = Net::LDAP::Filter.eq( self.attr_login, login )
            ldap.search(:base => self.base_dn,
                        :filter => user_filter & login_filter,
                        :attributes => attrs,
                        :return_result => false) do |entry|
              yield entry
            end
          end

          def ldapsync_active?
            settings && settings[:active]
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

          def pluralize(n, word)
            return word.present? ? "#{n} #{word}#{'s' if n != 1}" : n.to_s
          end

          def settings
            return @settings if @settings

            @settings = Setting.plugin_redmine_ldap_sync[self.name]
          end
        end
      end
    end
  end
end
