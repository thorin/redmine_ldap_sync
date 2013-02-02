require File.expand_path('../../test_helper', __FILE__)

class AuthSourceLdapTest < ActiveSupport::TestCase
  fixtures :auth_sources, :users, :settings, :custom_fields

  setup do
    Setting.clear_cache
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    AuthSourceLdap.activate_users = false
    AuthSourceLdap.running_rake = false
  end

  context "#sync_groups" do
    should "sync custom fields and create groups" do
      group_count, custom_value_count = Group.count, CustomValue.count

      @auth_source.sync_groups

      assert_equal group_count + 8, Group.count, "Group.count"
      assert_equal custom_value_count + 10, CustomValue.count, "CustomValue.count"

      group = Group.find_by_lastname('therss')
      assert_equal 'Therss Team Group', group.custom_field_values[0].value
    end

    should "not sync groups without fields_to_sync and create_groups" do
      @ldap_setting.group_fields_to_sync = []
      @ldap_setting.create_groups = false
      @ldap_setting.save

      assert_no_difference ['Group.count', 'CustomValue.count'] do
        @auth_source.sync_groups
      end
    end

    should "not sync groups with synchronization disabled" do
      @ldap_setting.active = false
      @ldap_setting.save

      assert_no_difference ['Group.count', 'CustomValue.count'] do
        @auth_source.sync_groups
      end
    end

    should "not sync groups with connect as user" do
      @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
      @auth_source.save

      assert_no_difference ['Group.count', 'CustomValue.count'] do
        @auth_source.sync_groups
      end
    end

    should "only sync custom fields without create_groups" do
      @ldap_setting.create_groups = false
      @ldap_setting.save
      group_count, custom_value_count = Group.count, CustomValue.count

      @auth_source.sync_groups

      assert_equal group_count, Group.count, "Group.count"
      assert_not_equal custom_value_count, CustomValue.count, "CustomValue.count"
    end
  end

  context "#sync_users" do
    setup do
      @ldap_setting.fixed_group = nil
      @ldap_setting.save
    end

    should "create users and groups" do
      user_count = User.count
      group_count = Group.count
      custom_value_count = CustomValue.count

      @auth_source.sync_users

      assert_equal user_count + 6, User.count, "User.count"
      assert_equal group_count + 8, Group.count, "Group.count"
      assert_equal custom_value_count + 22, CustomValue.count, "CustomValue.count"
    end

    should "not sync users when disabled" do
      @ldap_setting.active = false
      @ldap_setting.save

      assert_no_difference ['User.count', 'Group.count', 'CustomValue.count'] do
        @auth_source.sync_users
      end
    end

    should "not sync groups with connect as user" do
      @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
      @auth_source.save

      assert_no_difference ['User.count', 'Group.count', 'CustomValue.count'] do
        @auth_source.sync_users
      end
    end

    should "not create users without create users" do
      @ldap_setting.create_users = false
      @ldap_setting.save

      assert_no_difference ['User.count'] do
        @auth_source.sync_users
      end
    end

    should "sync users and groups without nested groups" do
      @ldap_setting.nested_groups = ''
      @ldap_setting.save

      assert_nil User.find_by_login 'systemhack'
      @auth_source.sync_users

      user = User.find_by_login 'systemhack'
      assert_not_nil user, 'User systemhack should exist'
      user_groups = Set.new(user.groups.map(&:name))
      assert_equal Set.new(%w(Anbely Sayeldas Worathest)), user_groups
    end

    should "sync users and groups with nested groups on parents" do
      @ldap_setting.nested_groups = 'on_parents'
      @ldap_setting.save

      assert_nil User.find_by_login 'systemhack'
      @auth_source.sync_users

      user = User.find_by_login 'systemhack'
      assert_not_nil user, 'User systemhack should exist'
      user_groups = Set.new(user.groups.map(&:name))
      assert_equal Set.new(%w(Anbely Enden Sayeldas Briklor Worathest Bluil)), user_groups
    end

    should "sync users and groups with nested groups on members" do
      @ldap_setting.nested_groups = 'on_members'
      @ldap_setting.save

      assert_nil User.find_by_login 'systemhack'
      @auth_source.sync_users

      user = User.find_by_login 'systemhack'
      assert_not_nil user, 'User systemhack should exist'
      user_groups = Set.new(user.groups.map(&:name))
      assert_equal Set.new(%w(Anbely Enden Sayeldas Briklor Worathest Bluil)), user_groups
    end

    should "lock disabled users" do
      user = User.find_by_login 'loadgeek'
      assert_not_nil user
      assert user.active?

      @ldap_setting.account_flags = 'description'
      @ldap_setting.account_disabled_test = "flags.include? 'Earheart'"
      @ldap_setting.save

      @auth_source.sync_users

      assert user.reload.locked?
    end

    should "not lock users when there's no account_flags" do
      @ldap_setting.account_flags = nil
      @ldap_setting.save

      @auth_source.sync_users

      assert_not_nil User.find_by_login 'tweetmicro'
      assert_not_nil User.find_by_login 'loadgeek'
    end

    should "write to stdout when running on rake" do
      old_stdout, $stdout = $stdout, StringIO.new

      AuthSourceLdap.running_rake!
      @auth_source.sync_users

      actual, $stdout = $stdout.string, old_stdout

      assert_include '-- Updating user \'loadgeek\'...', actual
      assert_include '-> 6 groups added', actual
    end
  end

  context "#sync_user" do
    setup do
      @user = User.find_by_login 'loadgeek'
    end
    should "not sync fields with no attrs to sync" do
      @ldap_setting.user_fields_to_sync = []
      @ldap_setting.save

      @auth_source.sync_user(@user)
      @user.reload
      assert_equal @user.mail, 'miscuser8@foo.bar'
      assert_equal @user.firstname, 'User'
      assert_equal @user.lastname, 'Misc'
      assert_equal @user.custom_field_values[0].value, nil
      assert_equal @user.custom_field_values[1].value, nil
    end

    should "not create groups without create groups" do
      @ldap_setting.create_groups = false
      @ldap_setting.save

      assert_nil Group.find_by_lastname 'Anbely'
      @auth_source.sync_user(@user)

      assert_nil Group.find_by_lastname 'Anbely'
    end

    should "sync with nested groups" do
      assert_not_include 'Iardum', @user.groups.map(&:name)
      @auth_source.sync_user(@user)

      assert_include 'Iardum', @user.groups.map(&:name)
    end

    should "sync without nested groups" do
      @ldap_setting.nested_groups = ''
      @ldap_setting.save

      assert_not_include 'Anbely', @user.groups.map(&:name)
      @auth_source.sync_user(@user)

      assert_not_include 'Anbely', @user.groups.map(&:name)
    end

    should "sync groups with membership on members" do
      @ldap_setting.group_membership = 'on_members'
      @ldap_setting.save

      assert_nil Group.find_by_lastname 'Issekin'
      assert_not_include 'Issekin', @user.groups.map(&:name)

      @auth_source.sync_user(@user)

      assert_include 'Issekin', @user.groups.map(&:name)
    end

    should "sync groups with membership on groups" do
      @ldap_setting.group_membership = 'on_groups'
      @ldap_setting.save

      assert_nil Group.find_by_lastname 'Issekin'
      assert_not_include 'Issekin', @user.groups.map(&:name)

      @auth_source.sync_user(@user)

      assert_include 'Issekin', @user.groups.map(&:name)
    end

    should "set or disable admin privilege" do
      @ldap_setting.admin_group = 'therss'
      @ldap_setting.save

      assert_false @user.admin?
      @auth_source.sync_user(@user)
      assert @user.reload.admin?

      @ldap_setting.admin_group = 'Itora'
      @ldap_setting.save

      @auth_source = AuthSource.find(@auth_source.id)
      @auth_source.sync_user(@user)
      assert_false @user.reload.admin?
    end

    should "not sync fields or admin privilege if locked" do
      @ldap_setting.admin_group = 'Enden'
      @ldap_setting.save
      @user.lock!

      @auth_source.sync_user(@user)
      assert_equal 'miscuser8@foo.bar', @user.mail
      assert_false @user.admin?
      assert_empty @user.groups
    end

    should "add to fixed group" do
      @ldap_setting.fixed_group = 'Fixed Group'
      @ldap_setting.save

      @auth_source.sync_user(@user)
      assert_include 'Fixed Group', @user.groups.map(&:name)
    end

    should "unlock(lock) if (not) member of required group" do
      @ldap_setting.required_group = 'Worathest'
      @ldap_setting.save

      assert @user.active?
      @auth_source.sync_user(@user)
      assert @user.reload.locked?

      @ldap_setting.required_group = 'therss'
      @ldap_setting.save

      @auth_source = AuthSource.find(@auth_source.id)
      @auth_source.sync_user(@user)
      assert @user.reload.active?
    end

    should "activate user if activate_users flag is set" do
      @user.lock!

      AuthSourceLdap.activate_users!
      @auth_source.sync_user(@user)
      assert @user.active?
    end

    should "sync with dynamic groups" do
      pending "not implemented yet"
    end

    should "sync without dynamic groups" do
      pending "not implemented yet"
    end
  end

  context "#try_login" do
    should "add to fixed group, create and synchronize a new user" do
      @ldap_setting.active = true
      @ldap_setting.fixed_group = 'ldap.users'
      @ldap_setting.nested_groups = 'on_parents'
      @ldap_setting.save

      assert_nil User.find_by_login 'systemhack'

      user = User.try_to_login('systemhack', 'password')

      assert_not_nil User.find_by_login 'systemhack'

      user_groups = Set.new(user.groups.map(&:name))
      assert_equal Set.new(%w(ldap.users Sayeldas Briklor Bluil Enden Anbely Worathest)), user_groups
      assert_equal 'da', user.custom_field_values[0].value
      assert_equal '303', user.custom_field_values[1].value
      assert_equal 'systemhack@fakemail.com', user.mail
      assert_equal 'Darryl', user.firstname
      assert_equal 'Ditto', user.lastname
    end

    should "synchronize existing users" do
      assert_not_nil user = User.find_by_login('loadgeek')
      assert_equal 'miscuser8@foo.bar', user.mail

      user = User.try_to_login('loadgeek', 'password')

      assert_not_nil user = User.find_by_login('loadgeek')

      user_groups = Set.new(user.groups.map(&:name))
      assert_equal Set.new(%w(therss ldap.users Bluil Issekin Iardum)), user_groups
      assert_equal 'pt', user.custom_field_values[0].value
      assert_equal '301', user.custom_field_values[1].value
      assert_equal 'loadgeek@fakemail.com', user.mail
      assert_equal 'Christian', user.firstname
      assert_equal 'Earheart', user.lastname
    end

    should "deny access to just now locked users" do
      @ldap_setting.required_group = 'Itora'
      @ldap_setting.save
      assert_nil User.try_to_login('systemhack', 'password')

      pending "Should block users locked by account_flags"
      assert_nil User.try_to_login('tweetmicro', 'password')
    end

    should "work with non ldap_auth_source users" do
      assert_not_nil User.try_to_login('jsmith', 'jsmith')
    end

    should "sync fields and groups with connect as user" do
      @auth_source.account = 'uid=$login,ou=Person,dc=redmine,dc=org'
      @auth_source.save

      assert_not_nil user = User.try_to_login('microunit', 'password')
      assert_equal 'microunit@fakemail.com', user.mail
    end
  end

end