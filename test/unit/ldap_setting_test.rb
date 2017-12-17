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

class LdapSettingTest < ActiveSupport::TestCase
  include ActiveModel::Lint::Tests

  fixtures :auth_sources, :users, :settings, :custom_fields
  fixtures :email_addresses if Redmine::VERSION::MAJOR >= 3

  def setup
    @auth_source = auth_sources(:auth_sources_001)
    @model = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    @ldap_setting = @model
  end

  # Replace this with your real tests.
  def test_save
    auth_source = auth_sources(:auth_sources_002)
    assert !Setting.plugin_redmine_ldap_sync[auth_source.id]['user_groups']
    setting = LdapSetting.find_by_auth_source_ldap_id(auth_source.id)
    setting.safe_attributes = {
      'active' => true,
      'groupname' => 'cn',
      'groups_base_dn' => 'groups_base_dn',
      'class_group' => 'group',
      'users_search_scope' => 'subtree',
      'class_user' => 'user',
      'group_membership' => 'on_members',
      'groupid' => 'groupid',
      'nested_groups' => '',
      'user_groups' => 'memberof',
      'sync_on_login' => '',
      'dyngroups' => ''
    }
    assert setting.save, setting.errors.full_messages.join(', ')
    assert Setting.plugin_redmine_ldap_sync[auth_source.id]['user_groups']
  end

  def test_should_strip_ldap_attributes
    @ldap_setting.safe_attributes = {
      'groupname' => ' cn ',
      'class_group' => ' group ',
      'class_user' => ' user ',
      'groupid' => ' groupid ',
      'user_groups' => ' memberof '
    }
    assert @ldap_setting.save
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
    assert_match /\A[^ ]+\z/, @ldap_setting.groupname
    assert_match /\A[^ ]+\z/, @ldap_setting.class_group
    assert_match /\A[^ ]+\z/, @ldap_setting.class_user
    assert_match /\A[^ ]+\z/, @ldap_setting.groupid
    assert_match /\A[^ ]+\z/, @ldap_setting.user_groups
  end

  def test_group_filter_should_be_validated
    @ldap_setting.group_search_filter = "(organizationalStatus=1"
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added?(:group_search_filter, :invalid)

    @ldap_setting.group_search_filter = "(organizationalStatus=1)"
    assert @ldap_setting.valid?
  end

  def test_should_validate_presence
    @ldap_setting.groups_base_dn = nil
    @ldap_setting.class_user = nil
    @ldap_setting.class_group = nil
    @ldap_setting.groupname = nil

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:class_user, :blank)
    assert @ldap_setting.errors.added?(:class_group, :blank)
    assert @ldap_setting.errors.added?(:groupname, :blank)

    @ldap_setting.groups_base_dn = 'ou=com,ou=redmine'
    @ldap_setting.class_user = 'user'
    @ldap_setting.class_group = 'group'
    @ldap_setting.groupname = 'cn'

    assert @ldap_setting.valid?
  end

  def test_should_validate_presence_when_membership_on_groups
    @ldap_setting.group_membership = 'on_groups'
    @ldap_setting.member = nil
    @ldap_setting.user_memberid = nil

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:member, :blank)
    assert @ldap_setting.errors.added?(:user_memberid, :blank)

    @ldap_setting.member = 'member'
    @ldap_setting.user_memberid = 'dn'

    assert @ldap_setting.valid?
  end

  def test_should_validate_presence_when_membership_on_members
    @ldap_setting.group_membership = 'on_members'
    @ldap_setting.user_groups = nil
    @ldap_setting.groupid = nil

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:user_groups, :blank)
    assert @ldap_setting.errors.added?(:groupid, :blank)

    @ldap_setting.user_groups = 'memberof'
    @ldap_setting.groupid = 'dn'

    assert @ldap_setting.valid?
  end

  def test_should_validate_presence_when_nested_on_members
    @ldap_setting.nested_groups = ''
    assert @ldap_setting.valid?

    @ldap_setting.nested_groups = 'on_members'
    @ldap_setting.parent_group = nil
    @ldap_setting.group_parentid = nil

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:parent_group, :blank)
    assert @ldap_setting.errors.added?(:group_parentid, :blank)

    @ldap_setting.parent_group = 'memberof'
    @ldap_setting.group_parentid = 'dn'

    assert @ldap_setting.valid?
  end

  def test_should_validate_presence_when_nested_on_groups
    @ldap_setting.nested_groups = ''
    assert @ldap_setting.valid?

    @ldap_setting.nested_groups = 'on_parents'
    @ldap_setting.member_group = nil
    @ldap_setting.group_memberid = nil

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:member_group, :blank)
    assert @ldap_setting.errors.added?(:group_memberid, :blank)

    @ldap_setting.member_group = 'member'
    @ldap_setting.group_memberid = 'dn'

    assert @ldap_setting.valid?
  end

  def test_should_validate_format_of_attributes
    @ldap_setting.group_memberid = 'aa invalid 2'
    @ldap_setting.account_flags = '$invalid'
    @ldap_setting.group_parentid = '-invalid'

    assert !@ldap_setting.valid?

    assert @ldap_setting.errors.added?(:group_memberid, :invalid)
    assert @ldap_setting.errors.added?(:account_flags, :invalid)
    assert @ldap_setting.errors.added?(:group_parentid, :invalid)

    @ldap_setting.group_memberid = 'theQ12342'
    @ldap_setting.account_flags = 'SAMAccountName'
    @ldap_setting.group_parentid = 'valid-name'

    assert @ldap_setting.valid?
  end

  def test_should_validate_user_ldap_attrs
    @ldap_setting.user_fields_to_sync = []
    @ldap_setting.user_ldap_attrs = {}
    assert @ldap_setting.valid?

    @ldap_setting.user_ldap_attrs = { 'mail' => 'email' }
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added? :user_group_fields, :invalid

    @ldap_setting.user_ldap_attrs = { '1' => 'uidNumber', '2' => 'desc ription' }
    assert !@ldap_setting.valid?
    assert !@ldap_setting.errors.added?(:user_group_fields, :invalid)
    assert_match /Uid Number/, @ldap_setting.errors.full_messages.join
    assert_no_match /Description/, @ldap_setting.errors.full_messages.join

    @ldap_setting.user_ldap_attrs = { '2' => 'description' }
    assert @ldap_setting.valid?
  end

  def test_should_validate_group_ldap_attrs
    @ldap_setting.group_fields_to_sync = []
    @ldap_setting.group_ldap_attrs = { '3' => 'description' }
    assert @ldap_setting.valid?

    @ldap_setting.group_ldap_attrs = { 'lastname' => 'c n' }
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added? :user_group_fields, :invalid
    assert @ldap_setting.errors.size == 1
  end

  def test_should_validate_user_fields_to_sync
    @ldap_setting.user_fields_to_sync = ['firstname', 'lastname', 'mail']
    assert @ldap_setting.valid?

    @ldap_setting.user_ldap_attrs = {}
    @ldap_setting.user_fields_to_sync = ['firstname', '1']
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.size == 1
    assert_match /Preferred Language/, @ldap_setting.errors.full_messages.join

    @ldap_setting.user_ldap_attrs = { '1' => 'preferredLanguage' }
    assert @ldap_setting.valid?
  end

  def test_should_validate_group_fields_to_sync
    @ldap_setting.group_fields_to_sync = ['lastname']
    assert !@ldap_setting.valid?

    @ldap_setting.group_ldap_attrs = {}
    @ldap_setting.group_fields_to_sync = ['3']
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.size == 1
    assert_match /Description/, @ldap_setting.errors.full_messages.join

    @ldap_setting.group_ldap_attrs = { '3' => 'description' }
    assert @ldap_setting.valid?
  end

  def test_should_validate_dyngroups_cache_ttl
    @ldap_setting.dyngroups_cache_ttl = nil
    @ldap_setting.dyngroups = ''
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.dyngroups = 'enabled'
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.dyngroups = 'enabled_with_ttl'
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added? :dyngroups_cache_ttl, :blank

    @ldap_setting.dyngroups_cache_ttl = 'one'
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added? :dyngroups_cache_ttl, :not_a_number

    @ldap_setting.dyngroups_cache_ttl = '12.1'
    assert !@ldap_setting.valid?
    assert @ldap_setting.errors.added? :dyngroups_cache_ttl, :not_an_integer

    @ldap_setting.dyngroups_cache_ttl = '50'
    assert @ldap_setting.valid?
  end

  def test_should_validate_sync_on_login
    @ldap_setting.sync_on_login = ''
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.sync_on_login = 'user_fields_and_groups'
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.sync_on_login = 'user_fields'
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.sync_on_login = 'invalid'
    assert !@ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')
  end

  def test_should_validate_account_locked_test
    @ldap_setting.account_locked_test = ''
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.account_locked_test = 'flags.include? "'
    assert !@ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.account_locked_test = 'flags.include? "D"'
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')
  end

  def test_should_validate_groupname_pattern
    @ldap_setting.groupname_pattern = ''
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.groupname_pattern = '?test$'
    assert !@ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')

    @ldap_setting.groupname_pattern = '\?test$'
    assert @ldap_setting.valid?, @ldap_setting.errors.full_messages.join(', ')
  end

  def test_should_return_field_for_user_ldap_attr
    @ldap_setting.user_ldap_attrs = { '1' => 'preferredLanguage', '2' => 'uidNumber' }
    @ldap_setting.save
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    assert_equal 'mail', @ldap_setting.user_field(:mail)
    assert_equal 'firstname', @ldap_setting.user_field(:givenname)
    assert_equal 'lastname', @ldap_setting.user_field(:sn)
    assert_equal '1', @ldap_setting.user_field(:preferredlanguage)
    assert_equal '2', @ldap_setting.user_field(:uidnumber)
    assert_nil @ldap_setting.user_field(:missing)
  end

  def test_should_return_field_for_group_ldap_attr
    @ldap_setting.group_ldap_attrs = { '3' => 'description' }
    @ldap_setting.save
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    assert_equal '3', @ldap_setting.group_field(:description)
    assert_nil @ldap_setting.group_field(:missing)
  end

  def test_should_return_ldap_attribute_for_field
    assert_equal %w( uid givenName sn mail cn description member ),
      @ldap_setting.ldap_attributes(:login, :firstname, :lastname, :mail, :groupname, :account_flags, :member_group)

    assert_equal [], @ldap_setting.ldap_attributes()

    assert_equal ['member'], @ldap_setting.ldap_attributes(:member_group)
  end

  def test_should_return_user_ldap_attrs_to_sync
    assert_equal Set.new(%w( givenName sn mail preferredLanguage uidNumber )),
      Set.new(@ldap_setting.user_ldap_attrs_to_sync)
  end

  def test_should_return_group_ldap_attrs_to_sync
    assert_equal %w( description ),
      @ldap_setting.group_ldap_attrs_to_sync
  end

  def test_groups_base_dn_should_not_be_required
    @ldap_setting.groups_base_dn = ''

    assert @ldap_setting.valid?

    assert !@ldap_setting.errors.added?(:groups_base_dn, :blank)
  end
end
