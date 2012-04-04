namespace :redmine do
  namespace :plugins do
    namespace :redmine_ldap_sync do
      desc "Synchronize redmine's users and groups with those on LDAP"
      task :sync_users => :environment do |t, args|
        if ENV['DRY_RUN']; end

        if defined?(ActiveRecord::Base)
          ActiveRecord::Base.logger = Logger.new(STDOUT)
          ActiveRecord::Base.logger.level = Logger::WARN
        end

        AuthSourceLdap.all.each do |as|
          puts "Synchronizing AuthSource #{as.name}..."
          as.sync_users
        end
      end
    end
  end
end
