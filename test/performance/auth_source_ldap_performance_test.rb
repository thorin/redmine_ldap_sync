require File.expand_path('../../test_helper', __FILE__)
require 'rails/performance_test_help'

class AuthSourceLdapPerformanceTest < ActionDispatch::PerformanceTest
  fixtures :auth_sources, :users, :groups_users, :settings, :custom_fields

  setup do
    clear_ldap_cache!
    Setting.clear_cache
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    AuthSourceLdap.activate_users = false
    AuthSourceLdap.running_rake = false
  end

  def test_sync_groups
    @auth_source.sync_groups
  end

  def test_sync_users
    @auth_source.sync_users
  end
end