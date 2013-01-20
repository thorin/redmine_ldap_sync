require File.expand_path('../../test_helper', __FILE__)

class LdapSettingsControllerTest < ActionController::TestCase
  # Replace this with your real tests.
  setup do
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    @request.session[:user_id] = 1
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:ldap_settings)
  end

  test "should get edit" do
    get :edit, id: @auth_source.id
    assert_response :success
  end

  test "should update ldap_setting" do
    put :update, id: @ldap_setting.id, ldap_setting: {
      auth_source_ldap_id: @auth_source_id,
      account_disabled_test: '',
      account_flags: '', 
      attributes_to_sync: '', 
      class_group: 'group', 
      class_user: 'user',
      create_groups: '',
      create_users: '',
      fixed_group: '', 
      group_memberid: '', 
      group_membership: 'on_members', 
      group_parentid: '',
      group_search_filter: '', 
      groupid: 'groupid', 
      groupname: '', 
      groupname_pattern: '', 
      groups_base_dn: 'groups_base_dn', 
      member: '', 
      member_group: '', 
      nested_groups: '', 
      parent_group: '',
      required_group: '', 
      sync_user_attributes: '', 
      user_groups: 'memberof', 
      user_memberid: ''
    }
    assert_redirected_to ldap_settings_path
    assert_match /success/, flash[:notice]
  end
end