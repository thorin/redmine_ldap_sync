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

if RUBY_VERSION >= '2.0.0'
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

module ActionController::TestCase::Behavior
  def process_patched(action, method, *args)
    options = args.extract_options!
    if options.present?
      params = options.delete(:params)
      options = options.merge(params) if params.present?
      args << options
    end
    process_unpatched(action, method, *args)
  end

  if Rails::VERSION::MAJOR < 5
    alias_method :process_unpatched, :process
    alias_method :process, :process_patched
  end
end