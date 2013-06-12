# encoding: utf-8
require 'simplecov'
require 'coveralls'

SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.start do
  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Helpers', 'app/helpers'
  add_group 'Libraries', 'lib'
  add_filter '/test/'
  add_filter 'init.rb'
  root File.expand_path(File.dirname(__FILE__) + '/../')
end

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