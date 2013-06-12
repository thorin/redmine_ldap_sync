require File.expand_path('../../../../../test/ui/base', __FILE__)
require File.expand_path('../../test_helper', __FILE__)

class Redmine::UiTest::LdapSettingTest < Redmine::UiTest::Base
  fixtures :auth_sources, :users, :settings, :custom_fields

  setup do
    log_user('admin', 'admin')
    visit '/admin/ldap_sync'
    within 'tr#ldap-config-1' do
      click_link 'LDAP test server'
    end
    assert_equal '/admin/ldap_sync/1/edit', current_path
  end

  def test_ldap_setting_test
    click_link 'Synchronization actions'
    select 'Enabled', :from => 'Dynamic groups'

    click_link 'Test'
    within 'div#tab-content-Test' do
      fill_in 'Users', :with => 'tweetmicro,systemhack,microunit,missing_user'
      fill_in 'Groups', :with => 'Iardum,MissingGroup'
      click_link 'Execute'
    end


    assert_selector '#test-result', :text => /User "tweetmicro":\s+Email = tweetmicro@fakemail.com/
    assert_selector '#test-result', :text => /User "microunit":\s+Email = microunit@fakemail.com/
    assert_selector '#test-result', :text => /User "missing_user": Not found/

    assert_selector '#test-result', :text => /Group "Iardum": No fields/
    assert_selector '#test-result', :text => /Group "MissingGroup": Not found/

    assert_selector '#test-result', :text => /Users enabled: a total of \d+\s+\[[^\]]*"microunit"[^\]]*\]/
    assert_selector '#test-result', :text => /Users disabled by flag: a total of \d+\s+\[[^\]]*"tweetmicro"[^\]]*\]/
    assert_selector '#test-result', :text => /Groups: a total of \d+\s+\[[^\]]*\]/
    assert_selector '#test-result', :text => /Dynamic groups: a total of \d+\s+.*MicroUsers:\s+\[[^\]]*microunit[^\]]*\]/
  end

  def test_base_settings
    select 'Samba LDAP', :from => 'Base settings'

    assert_equal 'sambaSamAccount', find_field('Users objectclass').value
    assert_equal 'member', find_field('Member users (group)').value

    select 'Active Directory (with nested groups)', :from => 'Base settings'

    assert_equal 'on_parents', find_field('Nested groups').value
    assert_equal 'flags.to_i & 2 != 0', find_field('Account disabled test').value
    assert_equal 'samaccountname', find_field('Group name (group)').value
    assert_equal 'useraccountcontrol', find_field('Account flags (user)').value
    assert_equal 'distinguishedname', find_field('Groupid (group)').value
    assert_equal 'member', find_field('Member groups (group)').value
    assert_equal 'distinguishedname', find_field('Memberid (group)').value
  end

  def test_group_membership
    select 'On the user class', :from => 'Group membership'

    assert !find_field('Member users (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Memberid (user)').visible? rescue Capybara::ElementNotFound
    assert find_field('Groups (user)').visible?
    assert find_field('Groupid (group)').visible?

    select 'On the group class', :from => 'Group membership'

    assert !find_field('Groups (user)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Groupid (group)').visible? rescue Capybara::ElementNotFound
    assert find_field('Member users (group)').visible?
    assert find_field('Memberid (user)').visible?
  end

  def test_nested_groups
    select 'Disabled', :from => 'Nested groups'

    assert !find_field('Member groups (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Memberid (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Parent groups (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Parentid (group)').visible? rescue Capybara::ElementNotFound

    select 'Membership on the parent class', :from => 'Nested groups'

    assert !find_field('Parent groups (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Parentid (group)').visible? rescue Capybara::ElementNotFound
    assert find_field('Member groups (group)').visible?
    assert find_field('Memberid (group)').visible?

    select 'Membership on the member class', :from => 'Nested groups'

    assert !find_field('Member groups (group)').visible? rescue Capybara::ElementNotFound
    assert !find_field('Memberid (group)').visible? rescue Capybara::ElementNotFound
    assert find_field('Parent groups (group)').visible?
    assert find_field('Parentid (group)').visible?
  end
end