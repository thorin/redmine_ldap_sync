# encoding: utf-8
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

Rails.backtrace_cleaner.remove_silencers!

class ActiveSupport::TestCase
  self.fixture_path = File.expand_path(File.dirname(__FILE__) + '/fixtures')

  def clear_ldap_cache!
    FileUtils.rm_rf Rails.root.join("tmp/ldap_cache")
  end
end

class ActionDispatch::IntegrationTest
  self.fixture_path = File.expand_path(File.dirname(__FILE__) + '/fixtures')
end