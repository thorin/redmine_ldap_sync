module RedmineLdapSync
  module RedmineExt
    module UserPatch
      def self.included(base)
        base.class_eval do
          after_create :add_to_domain_group
          
          def add_to_domain_group
            return unless auth_source && auth_source.auth_method_name == 'LDAP'

            group_name = Setting.plugin_redmine_ldap_sync[auth_source.name][:domain_group]
            return unless group_name.present?

            domain_group = Group.find_by_lastname(group_name)
            domain_group = Group.create(:lastname => group_name) unless domain_group
            domain_group.users << self
            
            save
          end

        end
      end
    end
  end
end
