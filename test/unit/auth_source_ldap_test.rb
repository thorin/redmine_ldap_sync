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

class AuthSourceLdapTest < ActiveSupport::TestCase
  fixtures :auth_sources, :users, :groups_users, :settings, :custom_fields, :roles, :projects, :members, :member_roles
  fixtures :email_addresses if Redmine::VERSION::MAJOR >= 3

  setup do
    clear_ldap_cache!
    Setting.clear_cache
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    AuthSourceLdap.activate_users = false
    AuthSourceLdap.running_rake = false
  end

  test "#sync_groups should sync custom fields and create groups" do
    group_count, custom_value_count = Group.count, CustomValue.count

    @auth_source.sync_groups

    assert_equal group_count + 11, Group.count, "Group.count"
    assert_equal custom_value_count + 14, CustomValue.count, "CustomValue.count"

    group = Group.find_by_lastname('therß')
    assert_equal 'Therß Team Group', group.custom_field_values[0].value
  end

  test "#sync_groups should not sync groups without fields_to_sync and create_groups" do
    @ldap_setting.group_fields_to_sync = []
    @ldap_setting.create_groups = false
    assert @ldap_setting.save,  @ldap_setting.errors.full_messages.join(', ')

    assert_no_difference ['Group.count', 'CustomValue.count'] do
      @auth_source.sync_groups
    end
  end

  test "#sync_groups should not sync groups with synchronization disabled" do
    @ldap_setting.active = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_no_difference ['Group.count', 'CustomValue.count'] do
      @auth_source.sync_groups
    end
  end

  test "#sync_groups should not sync groups with connect as user" do
    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    assert @auth_source.save, @auth_source.errors.full_messages.join(', ')

    assert_no_difference ['Group.count', 'CustomValue.count'] do
      @auth_source.sync_groups
    end
  end

  test "#sync_groups should only sync custom fields without create_groups" do
    @ldap_setting.create_groups = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    group_count, custom_value_count = Group.count, CustomValue.count

    @auth_source.sync_groups

    assert_equal group_count, Group.count, "Group.count"
    assert_not_equal custom_value_count, CustomValue.count, "CustomValue.count"
  end

  test "#sync_groups should sync dynamic groups and leave the cache fresh" do
    @ldap_setting.dyngroups = 'enabled'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    assert !@auth_source.send(:dyngroups_fresh?)
    clear_ldap_cache!

    @auth_source.sync_groups

    assert @auth_source.send(:dyngroups_fresh?), 'Cache is fresh'
    assert @auth_source.send(:dyngroups_cache).fetch('uid=microunit,ou=Person'), 'Find microunit cached groups'
  end

  test "#sync_groups should dynamic groups cache should expire" do
    @ldap_setting.dyngroups = 'enabled_with_ttl'
    @ldap_setting.dyngroups_cache_ttl = '2'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_groups

    now = Time.current + 3.minutes
    Time.stubs(:now).returns(now)

    assert !@auth_source.send(:dyngroups_fresh?)
  end

  test "#create_and_sync_group should fill in mandatory fields with the default value if their not present" do
    cf = GroupCustomField.create!(
        :name => 'email', :field_format => 'string',
        :is_required => true, :default_value => 'no email'
    )
    @ldap_setting.group_fields_to_sync << cf.id.to_s
    @ldap_setting.group_ldap_attrs[cf.id.to_s] = 'email'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.send(:create_and_sync_group, {:cn => ['Smuaddan']}, :cn)
    assert_equal 'no email', Group.find_by_lastname('Smuaddan').custom_field_value(cf)
  end

  test "#sync_users should create users and groups" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user_count = User.count
    group_count = Group.count
    custom_value_count = CustomValue.count

    @auth_source.sync_users

    assert_equal user_count + 5, User.count, "User.count"
    assert_equal group_count + 10, Group.count, "Group.count"
    assert_equal custom_value_count + 26, CustomValue.count, "CustomValue.count"
  end

  test "#sync_users should create users and groups without sync attrs" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    CustomField.delete_all
    @ldap_setting.user_fields_to_sync = nil
    @ldap_setting.group_fields_to_sync = nil
    @ldap_setting.user_ldap_attrs = nil
    @ldap_setting.group_ldap_attrs = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    Setting.clear_cache

    user_count = User.count
    group_count = Group.count

    @auth_source.sync_users

    assert_equal user_count + 5, User.count, "User.count"
    assert_equal group_count + 10, Group.count, "Group.count"
  end

  test "#sync_users should not sync users when disabled" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.active = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_no_difference %w(User.count Group.count CustomValue.count) do
      @auth_source.sync_users
    end
  end

  test "#sync_users should not sync groups with connect as user" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    @auth_source.save

    assert_no_difference %w(User.count Group.count CustomValue.count) do
      @auth_source.sync_users
    end
  end

  test "#sync_users should not create users without create users" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.create_users = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_no_difference ['User.count'] do
      @auth_source.sync_users
    end
  end

  test "#sync_users should sync users and groups without nested groups" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.nested_groups = ''
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'systemhack'
    @auth_source.sync_users

    user = User.find_by_login 'systemhack'
    assert_not_nil user, 'User systemhack should exist'
    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(Anbely Säyeldas Worathest)), user_groups
  end

  test "#sync_users should sync users and groups with nested groups on parents" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.nested_groups = 'on_parents'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'systemhack'
    @auth_source.sync_users

    user = User.find_by_login 'systemhack'
    assert_not_nil user, 'User systemhack should exist'
    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(Anbely Enden Säyeldas Briklør Worathest Bluil)), user_groups
  end

  test "#sync_users should sync users and groups with nested groups on members" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.nested_groups = 'on_members'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'systemhack'
    @auth_source.sync_users

    user = User.find_by_login 'systemhack'
    assert_not_nil user, 'User systemhack should exist'
    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(Anbely Enden Säyeldas Briklør Worathest Bluil)), user_groups
  end

  test "#sync_users should lock disabled users" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user = User.find_by_login 'loadgeek'
    assert_not_nil user
    assert user.active?

    @ldap_setting.account_flags = 'description'
    @ldap_setting.account_locked_test = "flags.include? 'Earheart'"
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_users

    assert user.reload.locked?
  end

  test "#sync_users should remove deleted users from all groups and projects" do
    user = User.find_by_login 'someone'
    assert_not_nil user
    assert user.active?

    refute user.groups.empty?
    refute user.memberships.empty?

    @auth_source.sync_users

    assert user.reload.locked?

    assert user.memberships.empty?
    assert user.groups.empty?
  end

  test "#sync_users should not lock users when there's no account_flags" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.account_flags = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_users

    assert_not_nil User.find_by_login 'tweetmicro'
    assert_not_nil User.find_by_login 'loadgeek'
  end

  test "#sync_users should show an user's name when its mail address has already been used" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    AuthSourceLdap.running_rake!
    AuthSourceLdap.trace_level = :change

    old_stdout, $stdout = $stdout, StringIO.new

    User.find_by_login('rhill').update_attribute(:mail, 'systemhack@fakemail.com')

    @auth_source.sync_users

    actual, $stdout = $stdout.string, old_stdout
    if actual.include? 'Could not sync user \'systemhack\''
      assert_include 'robert hill', actual
    end
  end

  test "#sync_users should add both loadgeek and microunit to an utf-8 named group (\#93)" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    group_name = 'IT отдел Системные'
    assert_nil Group.find_by_lastname group_name

    @auth_source.sync_users

    user1 = User.find_by_login 'loadgeek'
    user2 = User.find_by_login 'microunit'

    assert_include group_name, user1.groups.map(&:lastname)
    assert_include group_name, user2.groups.map(&:lastname)
  end

  test "#sync_users should sync locked users" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user1 = User.find_by_login 'loadgeek'
    user1.lock!
    assert user1.locked?

    @auth_source.sync_users

    assert_include 'Issekin', user1.groups.map(&:lastname)
    assert_include 'Iardum', user1.groups.map(&:lastname)
    assert_include 'Bluil', user1.groups.map(&:lastname)
  end

  test "#sync_users should not activate locked users if activate_users flag is set" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.account_flags = 'description'
    @ldap_setting.account_locked_test = 'true'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user1 = User.find_by_login 'loadgeek'
    user1.lock!
    assert user1.locked?

    AuthSourceLdap.activate_users!
    @auth_source.sync_users
    assert user1.locked?
  end

  test "#sync_users script output should be verbose when running on rake with level :debug" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    old_stdout, $stdout = $stdout, StringIO.new

    AuthSourceLdap.running_rake!
    AuthSourceLdap.trace_level = :debug
    @auth_source.sync_users

    actual, $stdout = $stdout.string, old_stdout

    assert_include '-- Updating user \'loadgeek\' (User Misc)...', actual
    assert_include '-> 6 groups added', actual
  end

  test "#sync_users script output should be silent when running on rake with level :silent" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    old_stdout, $stdout = $stdout, StringIO.new

    AuthSourceLdap.running_rake!
    AuthSourceLdap.trace_level = :silent
    @auth_source.sync_users

    actual, $stdout = $stdout.string, old_stdout

    assert_equal '', actual
  end

  test "#sync_users script output should only show changes when running with level :changes" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    old_stdout, $stdout = $stdout, StringIO.new

    AuthSourceLdap.running_rake!
    AuthSourceLdap.trace_level = :change
    @auth_source.sync_users

    actual, $stdout = $stdout.string, old_stdout

    assert_not_include '-- Updating user \'loadgeek\'...', actual
    assert_include '[loadgeek] 5 groups added', actual
    assert_include '1 deleted', actual
    assert_include 'and 1 already created', actual
  end

  test "#sync_users should sync with dynamic groups" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.dyngroups = 'enabled'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    @auth_source.sync_users

    user = User.find_by_login('tweetsave')
    assert_include 'TweetUsers', user.groups.map(&:lastname)
  end

  test "#sync_users should sync with dynamic groups when running rake" do
    @ldap_setting.fixed_group = nil
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    old_stdout, $stdout = $stdout, StringIO.new

    AuthSourceLdap.running_rake!
    @ldap_setting.dyngroups = 'enabled'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    @auth_source.sync_users

    actual, $stdout = $stdout.string, old_stdout

    user = User.find_by_login('tweetsave')
    assert_include 'TweetUsers', user.groups.map(&:lastname)
  end

  test "#sync_users should sync without dynamic groups" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.dyngroups = ''
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    @auth_source.sync_users

    user = User.find_by_login('tweetsave')
    assert_not_include 'TweetUsers', user.groups.map(&:lastname)
  end

  test "#sync_users with a primary group configured should add users the group with nested groups on parents" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.primary_group = 'gidNumber'
    @ldap_setting.nested_groups = 'on_parents'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_users

    user = User.find_by_login('rubycalm')
    assert_include 'Rill', user.groups.map(&:lastname)

    user = User.find_by_login('tweetsave')
    assert_include 'Smuaddan', user.groups.map(&:lastname)
  end

  test "#sync_users with a primary group configured should add users the group with nested groups on members" do
    @ldap_setting.fixed_group = nil
    @ldap_setting.primary_group = 'gidNumber'
    @ldap_setting.nested_groups = 'on_members'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_users

    user = User.find_by_login('rubycalm')
    assert_include 'Rill', user.groups.map(&:lastname)

    user = User.find_by_login('tweetsave')
    assert_include 'Smuaddan', user.groups.map(&:lastname)
  end

  test "#sync_users should not find any users with one level scope user search" do
    @ldap_setting.users_search_scope = 'onelevel'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user_count = User.count

    @auth_source.sync_users

    assert_equal user_count, User.count, "User.count"
  end

  test "#sync_user should not sync fields with no attrs to sync" do
    @user = users(:loadgeek)
    @ldap_setting.user_fields_to_sync = []
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_user(@user)
    @user.reload
    assert_equal 'miscuser8@foo.bar', @user.mail
    assert_equal 'User', @user.firstname
    assert_equal 'Misc', @user.lastname
    assert_include @user.custom_field_values[0].value, ['en',nil]
    assert_include @user.custom_field_values[1].value, ['0', nil]
  end

  test "#sync_user should delete groups" do
    @user = users(:loadgeek)
    assert_include 'rynever', @user.groups.map(&:name)

    @auth_source.sync_user(@user)

    @user.reload
    assert_not_include 'rynever', @user.groups.map(&:name)
  end

  test "#sync_user should not create groups without create groups" do
    @user = users(:loadgeek)
    @ldap_setting.create_groups = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil Group.find_by_lastname 'Anbely'
    @auth_source.sync_user(@user)

    assert_nil Group.find_by_lastname 'Anbely'
  end

  test "#sync_user should sync with nested groups" do
    @user = users(:loadgeek)
    assert_not_include 'Iardum', @user.groups.map(&:name)
    @auth_source.sync_user(@user)

    assert_include 'Iardum', @user.groups.map(&:name)
  end

  test "#sync_user should sync without nested groups" do
    @user = users(:loadgeek)
    @ldap_setting.nested_groups = ''
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_not_include 'Anbely', @user.groups.map(&:name)
    @auth_source.sync_user(@user)

    assert_not_include 'Anbely', @user.groups.map(&:name)
  end

  test "#sync_user should sync groups with membership on members" do
    @user = users(:loadgeek)
    @ldap_setting.group_membership = 'on_members'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil Group.find_by_lastname 'Issekin'
    assert_not_include 'Issekin', @user.groups.map(&:name)

    @auth_source.sync_user(@user)

    assert_include 'Issekin', @user.groups.map(&:name)
  end

  test "#sync_user should sync groups with membership on groups" do
    @user = users(:loadgeek)
    @ldap_setting.group_membership = 'on_groups'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil Group.find_by_lastname 'Issekin'
    assert_not_include 'Issekin', @user.groups.map(&:name)

    @auth_source.sync_user(@user)

    assert_include 'Issekin', @user.groups.map(&:name)
  end

  test "#sync_user should set or disable admin privilege" do
    @user = users(:loadgeek)
    @ldap_setting.admin_group = 'therß'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert !@user.admin?
    @auth_source.sync_user(@user)
    assert @user.reload.admin?

    @ldap_setting.admin_group = 'Itora'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source = AuthSource.find(@auth_source.id)
    @auth_source.sync_user(@user)
    assert !@user.reload.admin?
  end

  test "#sync_user should not sync fields or admin privilege if locked" do
    @user = users(:loadgeek)
    @ldap_setting.admin_group = 'Enden'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')
    @user.lock!

    groups_before = @user.groups
    @auth_source.sync_user(@user)
    assert_equal 'miscuser8@foo.bar', @user.mail
    assert !@user.admin?
    assert_equal groups_before, @user.groups
  end

  test "#sync_user should add to fixed group" do
    @user = users(:loadgeek)
    @ldap_setting.fixed_group = 'Fixed Group'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_user(@user)
    assert_include 'Fixed Group', @user.groups.map(&:name)
  end

  test "#sync_user should unlock(lock) if (not) member of required group" do
    @user = users(:loadgeek)
    @ldap_setting.required_group = 'Worathest'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert @user.active?
    @auth_source.sync_user(@user)
    assert @user.reload.locked?

    @ldap_setting.required_group = 'therß'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source = AuthSource.find(@auth_source.id)
    @auth_source.sync_user(@user)
    assert @user.reload.active?
  end

  test "#sync_user should not fail with an user that doesn't exist on ldap and should remove all groups" do
    @user = users(:loadgeek)
    @ldap_setting.sync_on_login  = 'user_fields_and_groups'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    user = users(:someone)
    @auth_source.sync_user(user, nil, :try_to_login => true)

    assert user.locked?, "User 'someone' should be locked"
    assert_equal [], user.groups.map(&:name)
    assert_equal 'Some', user.firstname
    assert_equal 'One', user.lastname
    assert_equal 'someone@foo.bar', user.mail
  end

  test "#sync_user should activate user if activate_users flag is set" do
    @user = users(:loadgeek)
    @user.lock!

    AuthSourceLdap.activate_users!
    @auth_source.sync_user(@user)
    assert @user.active?
  end

  test "#sync_user should fill in mandatory fields with the default value if their not present if set to sync" do
    @user = users(:loadgeek)
    cf = UserCustomField.create!(
        :name => 'group', :field_format => 'string',
        :is_required => true, :default_value => 'none'
    )
    @ldap_setting.user_fields_to_sync << cf.id.to_s
    @ldap_setting.user_ldap_attrs[cf.id.to_s] = 'group'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    @auth_source.sync_user(@user)
    assert_equal 'none', User.find(@user.id).custom_field_value(cf)
  end

  test "#sync_user should synchronize groups of users locked on ldap" do
    @user = users(:loadgeek)
    @ldap_setting.account_flags = 'description'
    @ldap_setting.account_locked_test = 'true'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert @user.active?, 'User should be active'
    assert_not_include 'Issekin', @user.groups.map(&:name)

    @auth_source.sync_user(@user, false, :try_to_login => true)

    assert @user.locked?, "User '#{@user.login}' should be locked"
    assert_include 'Issekin', @user.groups.map(&:name)
  end

  test "#try_login should work with wrong credentials" do
    assert_nil User.find_by_login 'invaliduser'

    user = User.try_to_login('invaliduser', 'password')
    assert_nil user

    user = User.try_to_login('systemhack', 'wrongpassword')
    assert_nil user
  end

  test "#try_login should work with incomplete users" do
    assert_nil User.find_by_login 'incomplete'

    user = User.try_to_login('incomplete', 'password')
    assert_not_nil user

    user.firstname = 'Incomplete'
    user.mail = 'incomplete@fakemail.com'
    user.save

    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(ldap.users Säyeldas Briklør Bluil Enden Anbely Worathest therß Iardum)), user_groups
    assert_equal 'pt', user.custom_field_values[0].value
    assert_equal '306', user.custom_field_values[1].value
    assert_equal 'incomplete@fakemail.com', user.mail
    assert_equal 'Incomplete', user.firstname
    assert_equal 'User', user.lastname
  end

  test "#try_login should deny access to incomplete users without the required group" do
    @ldap_setting.required_group = 'Rynever'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'incomplete'

    user = User.try_to_login('incomplete', 'password')
    assert_nil user
  end

  test "#try_login should deny access to incomplete users with a locked status" do
    @ldap_setting.account_flags = 'description'
    @ldap_setting.account_locked_test = "flags.include? 'without'"
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'incomplete'

    user = User.try_to_login('incomplete', 'password')
    assert_nil user
  end

  test "#try_login should show an user's name when its mail address has already been used" do
    AuthSourceLdap.running_rake!
    AuthSourceLdap.trace_level = :error

    old_stdout, $stdout = $stdout, StringIO.new

    User.find_by_login('rhill').update_attribute(:mail, 'loadgeek@fakemail.com')

    assert User.find_by_login 'loadgeek'

    user = User.try_to_login('loadgeek', 'password')

    actual, $stdout = $stdout.string, old_stdout
    assert_include('Robert Hill', actual) unless actual.empty?
  end

  test "with login as user #try_login should work with incomplete users" do
    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    @auth_source.save

    assert_nil User.find_by_login 'incomplete'

    user = User.try_to_login('incomplete', 'password')
    assert_not_nil user

    user.firstname = 'Incomplete'
    user.password = 'password'
    user.password_confirmation = 'password'
    user.mail = 'incomplete@fakemail.com'
    user.save

    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(ldap.users Säyeldas Briklør Bluil Enden Anbely Worathest therß Iardum)), user_groups
    assert_equal '306', user.custom_field_values[1].value
    assert_equal 'incomplete@fakemail.com', user.mail
    assert_equal 'Incomplete', user.firstname
  end

  test "with login as user #try_login should deny access to incomplete users with a locked status" do
    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    @auth_source.save

    @ldap_setting.account_flags = 'description'
    @ldap_setting.account_locked_test = "flags.include? 'without'"
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'incomplete'

    user = User.try_to_login('incomplete', 'password')
    assert_nil user
  end

  test "#try_login should add to fixed group, create and synchronize a new user" do
    @ldap_setting.active = true
    @ldap_setting.fixed_group = 'ldap.users'
    @ldap_setting.nested_groups = 'on_parents'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login 'systemhack'

    user = User.try_to_login('systemhack', 'password')

    assert_not_nil User.find_by_login 'systemhack'

    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(ldap.users Säyeldas Briklør Bluil Enden Anbely Worathest)), user_groups
    assert_equal 'da', user.custom_field_values[0].value
    assert_equal '303', user.custom_field_values[1].value
    assert_equal 'systemhack@fakemail.com', user.mail
    assert_equal 'Darryl', user.firstname
    assert_equal 'Ditto', user.lastname
  end

  test "#try_login should synchronize existing users" do
    @loadgeek = users(:loadgeek)
    assert_equal 'miscuser8@foo.bar', @loadgeek.mail

    assert_not_nil user = User.try_to_login('loadgeek', 'password')

    user_groups = Set.new(user.groups.map(&:name))
    assert_equal Set.new(%w(therß ldap.users Bluil Issekin Iardum) <<
     'IT отдел Системные'), user_groups
    assert_equal 'pt', user.custom_field_values[0].value
    assert_equal '301', user.custom_field_values[1].value
    assert_equal 'loadgeek@fakemail.com', user.mail
    assert_equal 'Christián', user.firstname
    assert_equal 'Earheart', user.lastname
  end

  test "#try_login should deny access to just now locked users" do
    @ldap_setting.required_group = 'Issekin'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert User.try_to_login('loadgeek', 'password')

    assert_nil User.try_to_login('systemhack', 'password')
    assert_nil User.try_to_login('tweetmicro', 'password')
  end

  test "#try_login should work with non ldap_auth_source users" do
    assert_not_nil User.try_to_login('jsmith', 'jsmith')
  end

  test "#try_login should sync fields and groups with connect as user" do
    @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
    @auth_source.save

    assert_not_nil user = User.try_to_login('microunit', 'password')
    assert_equal 'microunit@fakemail.com', user.mail
  end

  test "#try_login should not sync or lock if sync on login is disabled" do
    @loadgeek = users(:loadgeek)
    @ldap_setting.sync_on_login = ''
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    groups = @loadgeek.groups

    user = User.try_to_login('loadgeek', 'password')
    assert_equal 'miscuser8@foo.bar', user.mail
    assert_equal ['rynever'], user.groups.map(&:lastname)
  end

  test "#try_login should not sync groups if sync groups on login is disabled" do
    @ldap_setting.sync_on_login = 'user_fields'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.try_to_login('tweetmicro', 'password')

    assert_not_nil user = User.try_to_login('loadgeek', 'password')

    assert_equal ['rynever'], user.groups.map(&:lastname)
    assert_equal 'loadgeek@fakemail.com', user.mail
    assert_equal 'pt', user.custom_field_values[0].value
    assert_equal '301', user.custom_field_values[1].value
  end

  # Ldap sync keeps locking AD users trying to login (#108)
  test "#try_login should not lock users if disabled on settings" do
    @ldap_setting.required_group = 'missing_group'
    @ldap_setting.sync_on_login = 'user_fields_and_groups'
    @ldap_setting.active = false
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_not_nil user = User.try_to_login('loadgeek', 'password')
    assert user.active?
  end

  # Ldap sync keeps locking AD users trying to login (#108)
  test "#try_login should allow access to members of the required group with sync fields and groups" do
    @ldap_setting.required_group = 'therß'
    @ldap_setting.sync_on_login = 'user_fields_and_groups'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_not_nil user = User.try_to_login('loadgeek', 'password')
    assert user.active?
  end

  # Ldap sync keeps locking AD users trying to login (#108)
  test "#try_login should allow access to members of the required group with sync fields" do
    @ldap_setting.required_group = 'rynever'
    @ldap_setting.sync_on_login = 'user_fields'
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_not_nil user = User.try_to_login('loadgeek', 'password')
    assert user.active?
  end

  test "#ldap_users should return the users sorted" do
    @auth_source.send(:ldap_users).values.each do |users|
      next if users.empty?
      users = users.to_a
      users[0..-2].zip(users[1..-1]).each do |a, b|
        assert_operator a, :<=, b
      end
    end
  end

  test "#ldap_users should filter the users if the filter is enabled" do
    @auth_source.filter = '(uid=e*)'
    @auth_source.save!

    users = @auth_source.send(:ldap_users)
    assert users[:enabled].all? {|u| /^e.*$/i =~ u },
      "enabled_users = #{users[:enabled]}"

    assert users[:locked].none? {|u| /^e.*$/i =~ u },
      "locked_users = #{users[:locked]}"

    assert users[:deleted].none? {|u| /^e.*$/i =~ u },
      "locked_users = #{users[:deleted]}"
  end

  test "#find_or_create_user should sync mandatory fields on create even if not set to sync" do
    @ldap_setting.user_fields_to_sync = [ 'firstname' ]
    assert @ldap_setting.save, @ldap_setting.errors.full_messages.join(', ')

    assert_nil User.find_by_login('tweetmicro')
    assert_not_nil @auth_source.send(:find_or_create_user, 'tweetmicro'), 'Find or create'

    user = User.find_by_login('tweetmicro')
    assert_equal 'tweetmicro@fakemail.com', user.mail
    assert_equal 'Rae Croll', user.name
    assert_equal '302', user.custom_field_value(custom_fields(:uid_number))

    user.mail = 'tweetmicro@example.com'
    assert user.save, user.errors.full_messages.join(', ')
    @auth_source.sync_user(user)

    assert_equal 'tweetmicro@example.com', user.mail
  end
end
