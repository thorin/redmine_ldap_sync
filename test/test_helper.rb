require 'simplecov'
SimpleCov.start do
  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Helpers', 'app/helpers'
  add_group 'Libraries', 'lib'
  add_filter '/test/'
  add_filter 'init.rb'
  root File.expand_path(File.dirname(__FILE__) + '/../')
end

# Load the normal Rails helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

Rails.backtrace_cleaner.remove_silencers!

#use fixtures from redmine
class ActiveSupport::TestCase
  self.fixture_path = File.expand_path(File.dirname(__FILE__) + '/fixtures')

  def clear_ldap_cache!
    FileUtils.rm_rf Rails.root.join("tmp/ldap_cache")
  end
end
