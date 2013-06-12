require File.expand_path('../../../../../test/ui/base', __FILE__)
require File.expand_path('../../test_helper', __FILE__)

require 'simplecov'
SimpleCov.command_name 'test:ui'

class Redmine::UiTest::LoginTest < Redmine::UiTest::Base
  fixtures :auth_sources, :users, :settings, :custom_fields, :roles, :projects, :members, :member_roles

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
    select 'Português', :from => 'Language'

    click_on 'Submit'

    assert_equal my_account_path, current_path

    assert User.find_by_login('incomplete')
  end

end