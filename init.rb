require 'redmine'

Redmine::Plugin.register :redmine_ldap_sync do
  name 'Redmine Ldap Sync'
  author 'Ricardo Santos'
  author_url 'mailto:Ricardo Santos <ricardo.santos@vilt-group.com>?subject=redmine_ldap_sync'
  description 'Syncs users and groups with ldap'
  url 'https://github.com/thorin/redmine_ldap_sync'
  version '2.0.0.beta'
  requires_redmine :version_or_higher => '2.1.0'


  settings :default => HashWithIndifferentAccess.new()
  menu :admin_menu, :ldap_sync, { :controller => 'ldap_settings', :action => 'index' }, :caption => :label_ldap_synchronization
end

RedmineApp::Application.config.after_initialize do
  require 'project'

  require_dependency 'ldap_sync/core_ext'
  require_dependency 'ldap_sync/infectors'
end

# hooks
require_dependency 'ldap_sync/hooks'