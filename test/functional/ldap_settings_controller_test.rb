require File.expand_path('../../test_helper', __FILE__)

class LdapSettingsControllerTest < ActionController::TestCase
  fixtures :auth_sources, :users, :settings, :custom_fields

  setup do
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    @request.session[:user_id] = 1
  end

  def test_should_get_index
    get :index
    assert_response :success
    assert_not_nil assigns(:ldap_settings)

    assert_select "table tr", 3
    assert_select "a:content(LDAP test server)", 1
    assert_select "td:content(127.0.0.1)", 1
    assert_select "td:content(127.0.0.2)", 1
  end

  def test_should_get_base_settings_js
    get :base_settings, :format => 'js'
    assert_response :success
    assert_template 'ldap_settings/base_settings'
  end

  def test_should_redirect_to_get_edit_on_get_show
    get :show, :id => 1
    assert_redirected_to edit_ldap_setting_path(1)
  end

  def test_should_get_edit
    get :edit, :id => @auth_source.id
    assert_response :success
  end

  def test_should_get_404
    get :edit, :id => 999
    assert_response :not_found
  end

  def test_should_disable_ldap_setting
    # Given that
    assert @ldap_setting.active?, "LdapSetting must be enabled"
    assert_equal @ldap_setting.member_group, 'member'

    # When we do
    get :disable, :id => @ldap_setting.id
    assert_redirected_to ldap_settings_path
    assert_match /success/, flash[:notice]

    # We should have
    ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@ldap_setting.id)
    assert_equal ldap_setting.member_group, 'member', "LdapSetting is not the same"
    assert !ldap_setting.active?, "LdapSetting must be disabled"
  end

  def test_should_enable_ldap_setting
    # Given that
    @ldap_setting.active = false; @ldap_setting.save
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@ldap_setting.id)
    assert !@ldap_setting.active?, "LdapSetting must be disabled"
    assert_equal @ldap_setting.member_group, 'member'

    # When we do
    get :enable, :id => @ldap_setting.id
    assert_redirected_to ldap_settings_path
    assert_match /success/, flash[:notice]

    # We should have
    ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@ldap_setting.id)
    assert_equal ldap_setting.member_group, 'member', "LdapSetting is not the same"
    assert ldap_setting.active?, "LdapSetting must be enabled"
  end

  def test_should_fail_with_error
    put :update, :id => @ldap_setting.id, :ldap_setting => {
      :auth_source_ldap_id => @auth_source_id,
      :active => true,
      :groupname => 'cn',
      :groups_base_dn => 'groups_base_dn',
      :class_group => 'group',
      :class_user => nil,                     # Missing required field
      :group_membership => 'on_members',
      :groupid => 'groupid',
      :nested_groups => '',
      :user_groups => 'memberof',
      :sync_on_login => '',
      :dyngroups => ''
    }
    assert assigns(:ldap_setting).errors.added?(:class_user, :blank), "An error must be reported for :class_user"
    assert_response :success
  end

  def test_should_update_ldap_setting
    put :update, :id => @ldap_setting.id, :ldap_setting => {
      :auth_source_ldap_id => @auth_source_id,
      :active => true,
      :account_disabled_test => '',
      :account_flags => '',
      :attributes_to_sync => '',
      :class_group => 'group',
      :class_user => 'user',
      :create_groups => '',
      :create_users => '',
      :fixed_group => '',
      :group_memberid => '',
      :group_membership => 'on_members',
      :group_parentid => '',
      :group_search_filter => '',
      :groupid => 'groupid',
      :groupname => 'cn',
      :groupname_pattern => '',
      :groups_base_dn => 'groups_base_dn',
      :member => '',
      :member_group => '',
      :nested_groups => '',
      :parent_group => '',
      :required_group => '',
      :user_fields_to_sync => [],
      :group_fields_to_sync => [],
      :user_ldap_attrs => {},
      :group_ldap_attrs => {},
      :user_groups => 'memberof',
      :user_memberid => '',
      :sync_on_login => '',
      :dyngroups => ''
    }
    assert_redirected_to ldap_settings_path
    assert assigns(:ldap_setting).valid?
    assert_match /success/, flash[:notice]
  end

  def test_should_test
    put :test, :id => @ldap_setting.id, :format => 'text',
      :ldap_setting => @ldap_setting.send(:attributes),
      :ldap_test => { :test_users => 'example1', :test_groups => 'Therß' }

    assert_response :success
    assert_equal 'text/plain', response.content_type

    assert_match /User \"example1\":/,          response.body
    assert_match /Group \"Therß\":/,            response.body
    assert_match /Users enabled:/,              response.body
    assert_match /Users disabled by flag:/,     response.body
    assert_match /Admin users:/,                response.body
    assert_match /Groups:/,                     response.body
    assert_match /LDAP attributes on a user:/,  response.body
    assert_match /LDAP attributes on a group:/, response.body

    assert_not_match /ldap_test\.rb/, response.body, "Should not throw an error"
  end

  def test_should_validate_on_test
    @ldap_setting.dyngroups = 'invalid'

    put :test, :id => @ldap_setting.id, :format => 'text',
      :ldap_setting => @ldap_setting.send(:attributes),
      :ldap_test => { :test_users => 'example1', :test_groups => 'Therß' }

    assert_response :success
    assert_equal 'text/plain', response.content_type

    assert_match /Validation errors .* Dynamic groups/m,   response.body

    assert_not_match /ldap_test\.rb/, response.body, "Should not throw an error"
  end
end