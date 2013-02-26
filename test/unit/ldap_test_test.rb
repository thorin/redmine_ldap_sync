require File.expand_path('../../test_helper', __FILE__)

class LdapTestTest < ActiveSupport::TestCase
  include ActiveModel::Lint::Tests

  fixtures :auth_sources, :users, :groups_users, :settings, :custom_fields

  setup do
    Setting.clear_cache
    @auth_source    = auth_sources(:auth_sources_001)
    @ldap_setting   = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    @ldap_test      = @model = LdapTest.new(@ldap_setting)
  end

  def test_run_with_disabled_settings
    @ldap_setting.active = false;
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join
    @ldap_test = LdapTest.new(@ldap_setting)

    assert @ldap_test.setting.active?

    @ldap_test.run_with_users_and_groups([], [])
    assert_not_empty @ldap_test.non_dynamic_groups

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_one_or_more_users
    @ldap_test.run_with_users_and_groups(['loadgeek'], [])
    assert_equal 1, @ldap_test.users_at_ldap.size
    assert_include 'loadgeek', @ldap_test.users_at_ldap.keys

    @ldap_test = LdapTest.new(@ldap_setting)
    @ldap_test.run_with_users_and_groups(['MissingUser', 'tweetmicro'], [])
    assert_equal 2, @ldap_test.users_at_ldap.size
    assert_include 'MissingUser', @ldap_test.users_at_ldap.keys
    assert_equal :not_found, @ldap_test.users_at_ldap['MissingUser']
    assert_include 'tweetmicro', @ldap_test.users_at_ldap.keys
    assert_not_empty @ldap_test.users_at_ldap['tweetmicro'][:groups][:added]
    assert_equal 5, @ldap_test.users_at_ldap['tweetmicro'][:fields].size
    assert_empty @ldap_test.groups_at_ldap

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_one_or_more_groups
    @ldap_test.run_with_users_and_groups([], ['Rynever'])
    assert_equal 1, @ldap_test.groups_at_ldap.size
    assert_include 'Rynever', @ldap_test.groups_at_ldap.keys

    @ldap_test = LdapTest.new(@ldap_setting)
    @ldap_test.run_with_users_and_groups([], ['MissingGroup', 'Therß'])
    assert_equal 2, @ldap_test.groups_at_ldap.size
    assert_include 'MissingGroup', @ldap_test.groups_at_ldap.keys
    assert_equal :not_found, @ldap_test.groups_at_ldap['MissingGroup']
    assert_include 'Therß', @ldap_test.groups_at_ldap.keys
    assert_equal 1, @ldap_test.groups_at_ldap['Therß'][:fields].size
    assert_empty @ldap_test.users_at_ldap

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_users_and_groups
    @ldap_test.run_with_users_and_groups(['tweetsave', 'microunit'], ['Briklør', 'Rynever', 'Worathest'])
    assert_equal 2, @ldap_test.users_at_ldap.size
    assert_equal 3, @ldap_test.groups_at_ldap.size

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_no_group_fields_and_user_fields
    @ldap_setting.group_fields_to_sync = []
    @ldap_setting.user_fields_to_sync = []
    @ldap_setting.save

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Briklør', 'Therß'])
    assert_equal 0, @ldap_test.groups_at_ldap['Therß'][:fields].size
    assert_equal 3, @ldap_test.users_at_ldap['tweetsave'][:fields].size

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_disabled_users
    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Briklør'])
    assert_not_empty @ldap_test.user_changes[:disabled]

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_admin_group
    @ldap_setting.admin_group = 'Worathest'
    @ldap_setting.save

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Therß'])
    assert_not_empty @ldap_test.admin_users

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_required_group
    @ldap_setting.required_group = 'Bluil'
    @ldap_setting.save

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Therß'])
    assert_not_empty @ldap_test.users_disabled_by_group

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_dynamic_groups
    @ldap_setting.dyngroups = 'enabled'
    @ldap_setting.save

    @ldap_test.run_with_users_and_groups(['microunit'], ['Enden'])
    assert_include 'MicroUsers', @ldap_test.users_at_ldap['microunit'][:groups][:added]
    assert_not_empty @ldap_test.dynamic_groups

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_minimal_settings
    @ldap_setting.dyngroups = ''
    @ldap_setting.nested_groups = ''
    @ldap_setting.sync_on_login = ''
    @ldap_setting.account_flags = ''
    @ldap_setting.group_fields_to_sync = []
    @ldap_setting.user_fields_to_sync = []
    @ldap_setting.admin_group = ''
    @ldap_setting.required_group = ''
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join

    @ldap_test.run_with_users_and_groups([], [])
    assert_not_empty @ldap_test.messages
    assert_not_empty @ldap_test.user_changes[:enabled]
    assert_empty @ldap_test.user_changes[:disabled]
    assert_empty @ldap_test.users_at_ldap
    assert_empty @ldap_test.groups_at_ldap
    assert_not_empty @ldap_test.non_dynamic_groups
    assert_empty @ldap_test.dynamic_groups
    assert_empty @ldap_test.users_disabled_by_group
    assert_empty @ldap_test.admin_users

    assert_not_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_log_messages
    @ldap_test.run_with_users_and_groups([], [])
    assert_match /active, .* locked .* deleted/, @ldap_test.messages
  end

  def test_error_case
    @ldap_setting.account_disabled_test = "flags.include? [disabled]'"

    @ldap_test.run_with_users_and_groups([], [])

    assert_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end
end