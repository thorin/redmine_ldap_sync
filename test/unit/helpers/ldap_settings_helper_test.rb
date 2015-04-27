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

  def test_users_fields_list
    fields = [
      ["3", "Test Group"]
    ]

    assert_equal "    Description = Test Group\n", group_fields_list(fields)
  end

  def test_groups_fields_list
    fields = [
      ["1", "de"],
      ["2", "67123"]
    ]
    group_changes = {:added => ["group1", "group2"]}

    assert_equal "    Preferred Language = de\n" +
      "    Uid Number = 67123\n" +
      "    Groups = [\"group1\", \"group2\"]\n",
      user_fields_list(fields, group_changes)
  end

  def test_options_for_base_settings
    assert_not_equal 0, options_for_base_settings.size
  end

  def test_user_field_name
    assert_equal 'Preferred Language', user_field_name("1")
  end

  def test_group_field_name
    assert_equal 'Description', group_field_name("3")
  end

  def test_change_status_link
    @ldap_setting.active = true
    assert_match /Disable/, change_status_link(@ldap_setting)

    @ldap_setting.active = false
    assert_match /Enable/, change_status_link(@ldap_setting)
  end
end