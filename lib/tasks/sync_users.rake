namespace :redmine do
  namespace :plugins do
    namespace :ldap_sync do

      desc "Synchronize redmine's users fields and groups with those on LDAP"
      task :sync_users => :environment do |t, args|
        init_task

        AuthSourceLdap.activate_users! unless ENV['ACTIVATE_USERS'].nil?
        AuthSourceLdap.all.each do |as|
          puts "Synchronizing '#{as.name}' users..."
          as.sync_users
        end
      end

      desc "Synchronize redmine's groups fields with those on LDAP"
      task :sync_groups => :environment do |t, args|
        init_task

        AuthSourceLdap.all.each do |as|
          puts "Synchronizing '#{as.name}' groups..."
          as.sync_groups
        end
      end

      desc "Synchronize both redmine's users and groups with LDAP"
      task :sync_all => [:sync_groups, :sync_users]

      def init_task
        AuthSourceLdap.running_rake!

        if defined?(ActiveRecord::Base)
          ActiveRecord::Base.logger = Logger.new(STDOUT)
          ActiveRecord::Base.logger.level = Logger::WARN
        end

        unless ENV['DRY_RUN'].nil?
          puts "\n!!! Dry-run execution !!!\n"

          User.send :include, LdapSync::DryRun::User
          Group.send :include, LdapSync::DryRun::Group
        end
      end
    end

    namespace :redmine_ldap_sync do
      task :sync_users => 'redmine:plugins:ldap_sync:sync_users'
    end
  end
end