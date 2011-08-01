module RedmineLdapSync
  module RedmineExt
    module AuthSourceLdapPatch
      def self.included(base)
        base.class_eval do

          public
          def member_of?(login, group)
            ldap_con = initialize_ldap_con(self.account, self.account_password)
            login_filter = Net::LDAP::Filter.eq( self.attr_login, login )
            user_filter = Net::LDAP::Filter.eq( 'objectClass', 'user' )

            ldap_con.search(:base => self.base_dn,
                       :filter => user_filter & login_filter,
                       :attributes => ['memberof'],
                       :return_result => false) do |entry|
              return entry['memberof'].include? group
            end

          end


          def sync_groups(user)
            return unless ldapsync_active?

            changes = groups_changes(user)
            changes[:added].each do |groupname|
              next if user.groups.detect { |g| g.to_s == groupname }

              group = Group.find_by_lastname(groupname)
              group = Group.create(:lastname => groupname, :auth_source_id => self.id) unless group
              group.users << user
            end

            changes[:deleted].each do |groupname|
              next unless group = user.groups.detect { |g| g.to_s == groupname }

              group.users.delete(user)
            end
          end

          def sync_users
            return unless ldapsync_active?

            ldap_users[:disabled].each do |login|
              user = User.find_by_login(login)

              user.lock! if user
            end
            ldap_users[:enabled].each do |login|
              user = User.find_by_login(login)

              unless user
                attrs = get_user_dn(login)    
                user = User.create(attrs.except(:dn)) do |user|
                  user.login = login
                  user.language = Setting.default_language
                end
              end
              
              sync_groups(user)
            end
          end

          protected
          def ldap_users
            ldap_con = initialize_ldap_con(self.account, self.account_password)
            user_filter = Net::LDAP::Filter.eq( 'objectClass', 'user' )
            attr_enabled = 'userAccountControl'
            users = {:enabled => [], :disabled => []}
            
            ldap_con.search(:base => self.base_dn,
                            :filter => user_filter,
                            :attributes => [self.attr_login, attr_enabled],
                            :return_result => false) do |entry|
              if entry[attr_enabled][0].to_i & 2 != 0
                users[:disabled] << entry[self.attr_login][0]
              else
                users[:enabled] << entry[self.attr_login][0]
              end
            end

            users
          end

          def groups_changes(user)
            return unless ldapsync_active?
            changes = { :added => [], :deleted => [] }

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            login_filter = Net::LDAP::Filter.eq( self.attr_login, user.login )
            user_filter = Net::LDAP::Filter.eq( 'objectClass', 'user' )
            group_filter = Net::LDAP::Filter.eq( 'objectClass', 'group' )
            attr_groupname = Setting.plugin_redmine_ldap_sync[self.name][:attr_groupname]
            groupname_filter = /#{Setting.plugin_redmine_ldap_sync[self.name][:groupname_filter]}/
            groups_base_dn = Setting.plugin_redmine_ldap_sync[self.name][:groups_base_dn]

            # Faster, but requires all groups to be added to redmine with sync_groups
            #changes[:deleted] = user.groups.reject{|g| g.auth_source_id != self.id}.map(&:to_s) if user.groups
            ldap_con.open do |ldap|
              user_groups = user.groups.select {|g| groupname_filter =~ g.to_s}
              names_filter = user_groups.map {|g| Net::LDAP::Filter.eq( attr_groupname, g.to_s )}.reduce(:|)
              ldap.search(:base => groups_base_dn,
                          :filter => group_filter & names_filter,
                          :attributes => [attr_groupname],
                          :return_result => false) do |entry|
                changes[:deleted] << entry[attr_groupname][0]
              end if names_filter

              groups = []
              ldap.search(:base => self.base_dn,
                          :filter => user_filter & login_filter,
                          :attributes => ['memberof'],
                          :return_result => false) do |entry|
                groups = entry['memberof'].select {|g| g.end_with?(groups_base_dn)}
              end

              names_filter = groups.map{|g| Net::LDAP::Filter.eq( 'distinguishedName', g )}.reduce(:|)
              ldap.search(:base => groups_base_dn,
                          :filter => group_filter & names_filter,
                          :attributes => [attr_groupname],
                          :return_result => false) do |entry|
                group = entry[attr_groupname][0]
                changes[:added] << group if groupname_filter =~ group
              end if names_filter
            end

            changes[:deleted].reject! {|g| changes[:added].include?(g)}

            changes
          end
          
          def ldapsync_active?
            Setting.plugin_redmine_ldap_sync[self.name].present? && Setting.plugin_redmine_ldap_sync[self.name][:active]
          end
        end
      end
    end
  end
end
