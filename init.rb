require 'redmine'

Rails.logger.info 'Starting Redmine Ldap Sync plugin for RedMine'

Redmine::Plugin.register :redmine_ldap_sync do
  name 'Redmine - Ldap Sync'
  author 'Ricardo Santos'
  author_url 'mailto:Ricardo Santos <ricardo.santos@vilt-group.com>?subject=redmine_ldap_sync'
  description 'Syncs users and groups with ldap'
  url 'https://github.com/thorin/redmine_ldap_sync'
  version '1.3.0'
  requires_redmine :version_or_higher => '2.0.0'


  settings :default => HashWithIndifferentAccess.new(), :partial => 'settings/ldap_sync_settings'
end

RedmineApp::Application.config.after_initialize do
  require 'project'

  unless AuthSourceLdap.include? RedmineLdapSync::RedmineExt::AuthSourceLdapPatch
    AuthSourceLdap.send(:include, RedmineLdapSync::RedmineExt::AuthSourceLdapPatch)
  end
  unless SettingsHelper.include? RedmineLdapSync::RedmineExt::SettingsHelperPatch
    SettingsHelper.send(:include, RedmineLdapSync::RedmineExt::SettingsHelperPatch)
  end
  unless User.include? RedmineLdapSync::RedmineExt::UserPatch
    User.send(:include, RedmineLdapSync::RedmineExt::UserPatch)
  end
  unless ActiveSupport::Cache::FileStore.include? RedmineLdapSync::CoreExt::FileStorePatch
    ActiveSupport::Cache::FileStore.send(:include, RedmineLdapSync::CoreExt::FileStorePatch)
  end
  unless String.include? RedmineLdapSync::CoreExt::StringPatch
    String.send(:include, RedmineLdapSync::CoreExt::StringPatch)
  end
end
