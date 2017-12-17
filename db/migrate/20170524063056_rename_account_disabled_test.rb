class RenameAccountDisabledTest < ActiveRecord::Migration[4.2]
  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.id]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:account_locked_test] = settings[:account_disabled_test]
        settings.delete(:account_disabled_test)
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end

  def self.down
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.id]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:account_disabled_test] = settings[:account_locked_test]
        settings.delete(:account_locked_test)
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end
end
