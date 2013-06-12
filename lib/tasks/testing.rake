namespace :redmine do
  namespace :plugins do
    namespace :ldap_sync do
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
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/ui/**/*_test.rb"
        end

        desc 'Runs the plugins unit tests.'
        Rake::TestTask.new :units => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/unit/**/*_test.rb"
        end

        desc 'Runs the plugins functional tests.'
        Rake::TestTask.new :functionals => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/functional/**/*_test.rb"
        end

        desc 'Runs the plugins integration tests.'
        Rake::TestTask.new :integration => "db:test:prepare" do |t|
          t.libs << "test"
          t.verbose = true
          t.pattern = "plugins/#{PLUGIN_NAME}/test/integration/**/*_test.rb"
        end
      end


      namespace :coveralls do
        desc "Push latest coverage results to Coveralls.io"
        require 'coveralls/rake/task'

        ::SimpleCov.root = Rails.root.join("plugins/#{PLUGIN_NAME}/")
        Coveralls::RakeTask.new
        task :test => ['redmine:plugins:ldap_sync:test', 'coveralls:push']
      end
    end
  end
end