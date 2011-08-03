require 'redmine'
require 'dispatcher'

RAILS_DEFAULT_LOGGER.info 'Starting Redmine Ldap Sync plugin for RedMine'

Redmine::Plugin.register :redmine_ldap_sync do
  name 'Redmine - Ldap Sync'
  author 'Ricardo Santos'
  author_url 'mailto:Ricardo Santos <ricardo.santos@vilt-group.com>?subject=redmine_ldap_sync'
  description 'Syncs users and groups with ldap'
  url 'https://github.com/thorin/redmine_ldap_sync'
  version '1.1.0'
  requires_redmine :version_or_higher => '1.1.0'

  
  settings :default => HashWithIndifferentAccess.new(), :partial => 'settings/ldap_sync_settings'
end

Dispatcher.to_prepare :redmine_ldap_sync do
  require_dependency 'principal'
  require_dependency 'user'

  unless AuthSourceLdap.include? RedmineLdapSync::RedmineExt::AuthSourceLdapPatch
    AuthSourceLdap.send(:include, RedmineLdapSync::RedmineExt::AuthSourceLdapPatch)
  end
  unless SettingsHelper.include? RedmineLdapSync::RedmineExt::SettingsHelperPatch
    SettingsHelper.send(:include, RedmineLdapSync::RedmineExt::SettingsHelperPatch)
  end
  unless User.include? RedmineLdapSync::RedmineExt::UserPatch
    User.send(:include, RedmineLdapSync::RedmineExt::UserPatch)
  end
end
