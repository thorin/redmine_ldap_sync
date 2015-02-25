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
require 'rails/performance_test_help'

class AuthSourceLdapPerformanceTest < ActionDispatch::PerformanceTest
  fixtures :auth_sources, :users, :groups_users, :settings, :custom_fields
  fixtures :email_addresses if Redmine::VERSION::MAJOR >= 3

  setup do
    clear_ldap_cache!
    Setting.clear_cache
    @auth_source = auth_sources(:auth_sources_001)
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)

    AuthSourceLdap.activate_users = false
    AuthSourceLdap.running_rake = false
  end

  def test_sync_groups
    @auth_source.sync_groups
  end

  def test_sync_users
    @auth_source.sync_users
  end
end