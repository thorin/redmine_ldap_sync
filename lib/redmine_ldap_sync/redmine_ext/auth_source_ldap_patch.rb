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
              next if user.groups.detect { |g| g.to_s == groupname }

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
          end

          def sync_users
            return unless ldapsync_active?

            ldap_users[:disabled].each do |login|
              user = User.find_by_login_and_auth_source_id(login, self.id)

              user.lock! if user
            end

            groupname = settings[:must_be_member_of]
            
            ldap_users[:enabled].each do |login|
              user_is_fresh = false
              user = if create_users?
                User.find_or_create_by_login(login) do |user|
                  user.attributes = get_user_dn(login).except(:dn)
                  user.language = Setting.default_language
                  user_is_fresh = true
                end
              else
                User.find_by_login(login)
              end
            
              if user && user.auth_source_id == self.id
                sync_groups(user)
                sync_user_attributes(user) unless user_is_fresh
                user.lock! if groupname.present? && !user.groups.exists?(:lastname => groupname)
              end            
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

            users
          end

          def groups_changes(user)
            return unless ldapsync_active?
            changes = { :added => [], :deleted => [] }

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            group_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_group] )
            group_filter &= Net::LDAP::Filter.construct( settings[:group_search_filter] ) if settings[:group_search_filter].present?
            groupname_pattern = /#{settings[:groupname_pattern]}/
            groups_base_dn = settings[:groups_base_dn]
            attr_groupname = settings[:attr_groupname]
            attr_member = settings[:attr_member]

            # Faster, but requires all groups to be added to redmine with sync_groups
            #changes[:deleted] = user.groups.reject{|g| g.auth_source_id != self.id}.map(&:to_s) if user.groups
            ldap_con.open do |ldap|
              user_groups = user.groups.select {|g| groupname_pattern =~ g.to_s}
              names_filter = user_groups.map {|g| Net::LDAP::Filter.eq( attr_groupname, g.to_s )}.reduce(:|)
              ldap.search(:base => groups_base_dn,
                          :filter => group_filter & names_filter,
                          :attributes => [ attr_groupname ],
                          :return_result => false) do |entry|
                changes[:deleted] << entry[attr_groupname][0]
              end if names_filter

              user_dn = nil
              user_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_user] )
              login_filter = Net::LDAP::Filter.eq( self.attr_login, user.login )
              ldap.search(:base => self.base_dn,
                          :filter => user_filter & login_filter,
                          :attributes => ['dn'],
                          :return_result => false) do |entry|
                user_dn = entry['dn'][0]
              end

              groups = []
              member_filter = Net::LDAP::Filter.eq( attr_member, user_dn )
              ldap.search(:base => groups_base_dn,
                          :filter => group_filter & member_filter,
                          :attributes => [ attr_groupname ],
                          :return_result => false) do |entry|
                group = entry[attr_groupname][0]
                changes[:added] << group if groupname_pattern =~ group
              end if user_dn
            end

            changes[:deleted].reject! {|g| changes[:added].include?(g)}

            changes
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
		  
          def settings
            return @settings if @settings

            @settings = Setting.plugin_redmine_ldap_sync[self.name]
          end
        end
      end
    end
  end
end
