module RedmineLdapSync
  module RedmineExt
    module UserPatch
      def self.included(base)
        base.class_eval do
          after_create :add_to_auth_source_group
          
          def add_to_auth_source_group
            return unless auth_source && auth_source.auth_method_name == 'LDAP'

            groupname = auth_source.add_to_group
            return unless groupname.present?

            group = Group.find_or_create_by_lastname(groupname)
            group.users << self
            
            save
          end

          class << self
            def try_to_login_with_redmine_ldap_sync(login, password)
              user = try_to_login_without_redmine_ldap_sync(login, password)
              return nil unless user
              return user unless user.auth_source && user.auth_source.auth_method_name == 'LDAP'

              user.auth_source.sync_groups(user)
              user.auth_source.sync_user_attributes(user)
              user.auth_source.lock_unless_member_of(user)

              user if user.active?
            end
            alias_method_chain :try_to_login, :redmine_ldap_sync
          end

        end
      end
    end
  end
end
