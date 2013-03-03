# encoding: utf-8
require File.expand_path('../../../test_helper', __FILE__)

class LdapSettingsHelperTest < ActionView::TestCase
  include LdapSettingsHelper
  include Redmine::I18n

  fixtures :auth_sources, :settings, :custom_fields

  setup do
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(auth_sources(:auth_sources_001).id)
  end

  def test_groups_fields
    assert_equal ['Description'], group_fields.map(&:name)
    assert_equal ['no description'], group_fields.map(&:default_value)
    assert_equal ['description'], group_fields.map(&:ldap_attribute)

    @ldap_setting.group_ldap_attrs = {}
    assert_equal [''], group_fields.map(&:ldap_attribute)
  end

  def test_user_fields
    assert_equal ['Email', 'First name', 'Last name', 'Preferred Language', 'Uid Number'], user_fields.map(&:name).sort
    assert_equal ['', '', '', '0', 'en'], user_fields.map(&:default_value).sort
    assert_equal %w(givenName mail preferredLanguage sn uidNumber), user_fields.map(&:ldap_attribute).sort

    @ldap_setting.user_ldap_attrs = {}
    assert_equal ['', '', 'givenName', 'mail', 'sn'], user_fields.map(&:ldap_attribute).sort
  end

  def test_options_for_base_settings
    assert_not_equal 0, options_for_base_settings.size
  end
end