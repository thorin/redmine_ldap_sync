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
require File.expand_path('../base', __FILE__)

if RUBY_VERSION >= '2.0.0'
  require 'simplecov'
  SimpleCov.command_name 'UI Tests'
end

class Redmine::UiTest::LoginTest < Redmine::UiTest::Base
  fixtures :auth_sources, :users, :settings, :custom_fields, :roles, :projects, :members, :member_roles
  fixtures :email_addresses if Redmine::VERSION::MAJOR >= 3

  setup do
    visit '/login'
  end

  def test_login_with_existing_user
    within '#login-form' do
      fill_in 'Login', :with => 'loadgeek'
      fill_in 'Password', :with => 'password'
      click_on 'Login'
    end
    assert_equal my_page_path, current_path
  end

  def test_login_with_new_user
    within '#login-form' do
      fill_in 'Login', :with => 'systemhack'
      fill_in 'Password', :with => 'password'
      click_on 'Login'
    end
    assert_equal my_page_path, current_path
  end

  def test_login_with_incomplete_user
    within '#login-form' do
      fill_in 'Login', :with => 'incomplete'
      fill_in 'Password', :with => 'password'
      click_on 'Login'
    end

    assert_selector 'h2', :text => /Register/

    fill_in 'First name', :with => 'Incomplete'
    fill_in 'Last name', :with => 'User'
    fill_in 'Email', :with => 'incomplete@fakemail.com'
    select 'Nederlands', :from => 'Language'

    click_on 'Submit'

    assert_equal my_account_path, current_path

    assert User.find_by_login('incomplete')
  end

end