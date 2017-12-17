# encoding: utf-8
# Copyright (C) 2011-2013  The Redmine LDAP Sync Authors
#
# This file is part of Redmine LDAP Sync.
#
# Redmine LDAP Sync is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Redmine LDAP Sync is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Redmine LDAP Sync.  If not, see <http://www.gnu.org/licenses/>.
require File.expand_path('../../test_helper', __FILE__)

class LdapTestTest < ActiveSupport::TestCase
  include ActiveModel::Lint::Tests

  fixtures :auth_sources, :users, :groups_users, :settings, :custom_fields
  fixtures :email_addresses if Redmine::VERSION::MAJOR >= 3

  setup do
    Setting.clear_cache
    @auth_source    = auth_sources(:auth_sources_001)
    @ldap_setting   = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    @ldap_test      = @model = LdapTest.new(@ldap_setting)
  end

  def test_run_with_disabled_settings
    @ldap_setting.active = false;
    @ldap_test = LdapTest.new(@ldap_setting)

    assert @ldap_test.setting.active?

    @ldap_test.run_with_users_and_groups([], [])
    assert_not_equal 0, @ldap_test.non_dynamic_groups.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
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
    assert_not_equal 0, @ldap_test.users_at_ldap['tweetmicro'][:groups][:added].size
    assert_equal 5, @ldap_test.users_at_ldap['tweetmicro'][:fields].size, "#{@ldap_test.users_at_ldap['tweetmicro'][:fields]}"
    assert_equal 0, @ldap_test.groups_at_ldap.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
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
    assert_equal 0, @ldap_test.users_at_ldap.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_users_and_groups
    @ldap_test.run_with_users_and_groups(['tweetsave', 'microunit'], ['Briklør', 'Rynever', 'Worathest'])
    assert_equal 2, @ldap_test.users_at_ldap.size
    assert_equal 3, @ldap_test.groups_at_ldap.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_no_group_fields_and_user_fields
    @ldap_setting.group_fields_to_sync = []
    @ldap_setting.user_fields_to_sync = []

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Briklør', 'Therß'])
    assert_equal 0, @ldap_test.groups_at_ldap['Therß'][:fields].size

    # uid is required and should be set with the default value
    assert_equal 4, @ldap_test.users_at_ldap['tweetsave'][:fields].size, "#{@ldap_test.users_at_ldap['tweetsave'][:fields]}"

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_deleted_users
    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Briklør'])
    assert_not_equal 0, @ldap_test.user_changes[:locked].size
    assert_not_equal 0, @ldap_test.user_changes[:deleted].size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_admin_group
    @ldap_setting.admin_group = 'Worathest'

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Therß'])
    assert_not_equal 0, @ldap_test.admin_users.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_required_group
    @ldap_setting.required_group = 'Bluil'

    @ldap_test.run_with_users_and_groups(['tweetsave'], ['Therß'])
    assert_not_equal 0, @ldap_test.users_locked_by_group.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_with_dynamic_groups
    @ldap_setting.dyngroups = 'enabled'

    @ldap_test.run_with_users_and_groups(['microunit'], ['Enden'])
    assert_include 'MicroUsers', @ldap_test.users_at_ldap['microunit'][:groups][:added]
    assert_not_equal 0, @ldap_test.dynamic_groups.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
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

    @ldap_test.run_with_users_and_groups([], [])
    assert_not_equal 0, @ldap_test.messages.size
    assert_not_equal 0, @ldap_test.user_changes[:enabled].size
    assert_equal 0, @ldap_test.user_changes[:locked].size
    assert_equal 1, @ldap_test.user_changes[:deleted].size
    assert_equal 0, @ldap_test.users_at_ldap.size
    assert_equal 0, @ldap_test.groups_at_ldap.size
    assert_not_equal 0, @ldap_test.non_dynamic_groups.size
    assert_equal 0, @ldap_test.dynamic_groups.size
    assert_equal 0, @ldap_test.users_locked_by_group.size
    assert_equal 0, @ldap_test.admin_users.size

    assert_no_match /ldap_test\.rb/, @ldap_test.messages, "Should not throw an error"
  end

  def test_run_without_groups_base_dn_should_fail_on_open_ldap
    @ldap_setting.groups_base_dn = ''

    @ldap_test.run_with_users_and_groups([], [])
    assert_not_equal 0, @ldap_test.messages.size
    assert_equal 0, @ldap_test.non_dynamic_groups.size
    assert_equal 0, @ldap_test.dynamic_groups.size

    assert_match /ldap_test\.rb/, @ldap_test.messages, "Should throw an error"
  end

  def test_run_with_dynamic_bind_should_not_fail
    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    assert @auth_source.save, @auth_source.errors.full_messages.join(', ')
    ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    ldap_test    = LdapTest.new(ldap_setting)

    ldap_test.bind_user = 'admin'
    ldap_test.bind_password = 'password'
    ldap_test.run_with_users_and_groups([], [])
    assert_not_equal 15, ldap_test.messages.size
    assert_equal 15, ldap_test.non_dynamic_groups.size

    assert_no_match /ldap_test\.rb/, ldap_test.messages, "Should no throw an error"
  end

  def test_log_messages
    @ldap_test.run_with_users_and_groups([], [])
    assert_match /active, .* locked .* deleted/, @ldap_test.messages
  end

  def test_error_case
    @ldap_setting.account_locked_test = "flags.include? [disabled]'"

    @ldap_test.run_with_users_and_groups([], [])

    assert_match /ldap_test\.rb/, @ldap_test.messages, "Should throw an error"
  end

  def test_should_filter_the_list_of_groups_with_the_groupname_pattern
    @ldap_setting.groupname_pattern = "s$"
    @ldap_setting.dyngroups = 'enabled'

    @ldap_test.run_with_users_and_groups([], [])

    assert_equal 3, @ldap_test.non_dynamic_groups.size + @ldap_test.dynamic_groups.size
    assert_include 'Säyeldas', @ldap_test.non_dynamic_groups
  end

end