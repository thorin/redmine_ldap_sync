namespace :redmine do
  namespace :plugins do
    namespace :redmine_ldap_sync do
      desc "Synchronize redmine's users and groups with those on LDAP"
        task :sync_users => :environment do
          AuthSourceLdap.all.each {|as| as.sync_users}
        end
    end
  end
end

