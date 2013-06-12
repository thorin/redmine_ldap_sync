namespace :redmine do
  namespace :plugins do
    namespace :ldap_sync do
      require 'simplecov'
      PLUGIN_NAME='redmine_ldap_sync'

      desc 'Runs the ldap_sync tests.'
      task :test do
        Rake::Task["redmine:plugins:ldap_sync:test:units"].invoke
        Rake::Task["redmine:plugins:ldap_sync:test:functionals"].invoke
        Rake::Task["redmine:plugins:ldap_sync:test:integration"].invoke

        if RUBY_VERSION >= '1.9.3' && Redmine::VERSION.to_s >= '2.3.0'
          Rake::Task["redmine:plugins:ldap_sync:test:ui"].invoke
        end
      end

      namespace :test do
        desc 'Runs the plugins unit tests.'
        Rake::TestTask.new :ui => "db:test:prepare" do |t|
          SimpleCov.command_name 'test:ui'
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/ui/**/*_test.rb"
        end

        desc 'Runs the plugins unit tests.'
        Rake::TestTask.new :units => "db:test:prepare" do |t|
          SimpleCov.command_name 'test:units'
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/unit/**/*_test.rb"
        end

        desc 'Runs the plugins functional tests.'
        Rake::TestTask.new :functionals => "db:test:prepare" do |t|
          SimpleCov.command_name 'test:functionals'
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/functional/**/*_test.rb"
        end

        desc 'Runs the plugins integration tests.'
        Rake::TestTask.new :integration => "db:test:prepare" do |t|
          SimpleCov.command_name 'test:integration'
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/integration/**/*_test.rb"
        end
      end

      namespace :coveralls do
        desc "Push latest coverage results to Coveralls.io"
        task :test => 'redmine:plugins:ldap_sync:test' do
          ::SimpleCov.root Rails.root.join('plugins', "#{PLUGIN_NAME}")

          require 'coveralls'
          Coveralls.push!
        end
      end
    end
  end
end