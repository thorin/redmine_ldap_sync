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
require 'rake/testtask'

namespace :redmine do
  namespace :plugins do
    namespace :ldap_sync do
      LDAP_SYNC='redmine_ldap_sync'

      desc 'Runs the ldap_sync tests.'
      task :test do
        require 'redmine/version'
        Rake::Task["redmine:plugins:ldap_sync:test:units"].invoke
        Rake::Task["redmine:plugins:ldap_sync:test:functionals"].invoke
        Rake::Task["redmine:plugins:ldap_sync:test:integration"].invoke

        if RUBY_VERSION >= '1.9.3' && Redmine::VERSION.to_s >= '2.3.0'
          Rake::Task["redmine:plugins:ldap_sync:test:ui"].invoke
        end
      end

      namespace :test do
        desc 'Runs the plugins ui tests.'
        Rake::TestTask.new :ui => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{LDAP_SYNC}/test/ui/**/*_test.rb"
        end

        desc 'Runs the plugins unit tests.'
        Rake::TestTask.new :units => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{LDAP_SYNC}/test/unit/**/*_test.rb"
        end

        desc 'Runs the plugins functional tests.'
        Rake::TestTask.new :functionals => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{LDAP_SYNC}/test/functional/**/*_test.rb"
        end

        desc 'Runs the plugins integration tests.'
        Rake::TestTask.new :integration => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{LDAP_SYNC}/test/integration/**/*_test.rb"
        end
      end

      namespace :coveralls do
        desc "Push latest coverage results to Coveralls.io"
        task :test => 'redmine:plugins:ldap_sync:test' do
          require 'simplecov'
          ::SimpleCov.root Rails.root.join('plugins', "#{LDAP_SYNC}")

          require 'coveralls'
          Coveralls.push!
        end
      end
    end
  end
end
