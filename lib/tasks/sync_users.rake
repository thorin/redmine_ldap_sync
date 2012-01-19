namespace :redmine do
  namespace :plugins do
    namespace :redmine_ldap_sync do
      desc "Synchronize redmine's users and groups with those on LDAP"
      task :sync_users => :environment do
        AuthSourceLdap.all.each do |as|
          puts "Synchronizing AuthSource #{as.name}..."

          _dry_run = ENV['dry_run'].present?
          if _dry_run
            puts "\n!!! Dry-run execution !!!\n"
          end

          as.sync_users(_dry_run)
        end
      end
    end
  end
end
