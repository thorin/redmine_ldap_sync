require File.expand_path('../../test_helper', __FILE__)

class LdapSyncControllerTest < ActionController::TestCase
  # Replace this with your real tests.
  setup do
    @ldap_setting = ldap_settings(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:ldap_settings)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create ldap_setting" do
    assert_difference('LdapSetting.count') do
      post :create, ldap_setting: { account_disabled_test: @ldap_setting.account_disabled_test, account_flags: @ldap_setting.account_flags, attributes_to_sync: @ldap_setting.attributes_to_sync, class_group: @ldap_setting.class_group, class_user: @ldap_setting.class_user, create_groups: @ldap_setting.create_groups, create_users: @ldap_setting.create_users, fixed_group: @ldap_setting.fixed_group, group_memberid: @ldap_setting.group_memberid, group_membership: @ldap_setting.group_membership, group_parentid: @ldap_setting.group_parentid, group_search_filter: @ldap_setting.group_search_filter, groupid: @ldap_setting.groupid, groupname: @ldap_setting.groupname, groupname_pattern: @ldap_setting.groupname_pattern, groups_base_dn: @ldap_setting.groups_base_dn, member: @ldap_setting.member, member_group: @ldap_setting.member_group, nested_groups: @ldap_setting.nested_groups, parent_group: @ldap_setting.parent_group, required_group: @ldap_setting.required_group, sync_user_attributes: @ldap_setting.sync_user_attributes, user_groups: @ldap_setting.user_groups, user_memberid: @ldap_setting.user_memberid }
    end

    assert_redirected_to ldap_setting_path(assigns(:ldap_setting))
  end

  test "should show ldap_setting" do
    get :show, id: @ldap_setting
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @ldap_setting
    assert_response :success
  end

  test "should update ldap_setting" do
    put :update, id: @ldap_setting, ldap_setting: { account_disabled_test: @ldap_setting.account_disabled_test, account_flags: @ldap_setting.account_flags, attributes_to_sync: @ldap_setting.attributes_to_sync, class_group: @ldap_setting.class_group, class_user: @ldap_setting.class_user, create_groups: @ldap_setting.create_groups, create_users: @ldap_setting.create_users, fixed_group: @ldap_setting.fixed_group, group_memberid: @ldap_setting.group_memberid, group_membership: @ldap_setting.group_membership, group_parentid: @ldap_setting.group_parentid, group_search_filter: @ldap_setting.group_search_filter, groupid: @ldap_setting.groupid, groupname: @ldap_setting.groupname, groupname_pattern: @ldap_setting.groupname_pattern, groups_base_dn: @ldap_setting.groups_base_dn, member: @ldap_setting.member, member_group: @ldap_setting.member_group, nested_groups: @ldap_setting.nested_groups, parent_group: @ldap_setting.parent_group, required_group: @ldap_setting.required_group, sync_user_attributes: @ldap_setting.sync_user_attributes, user_groups: @ldap_setting.user_groups, user_memberid: @ldap_setting.user_memberid }
    assert_redirected_to ldap_setting_path(assigns(:ldap_setting))
  end

  test "should destroy ldap_setting" do
    assert_difference('LdapSetting.count', -1) do
      delete :destroy, id: @ldap_setting
    end

    assert_redirected_to ldap_settings_path
  end
end