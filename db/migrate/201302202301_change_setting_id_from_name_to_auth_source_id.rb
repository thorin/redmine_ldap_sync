class ChangeSettingIdFromNameToAuthSourceId < ActiveRecord::Migration[4.2]

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        all_settings[as.id] = settings
        all_settings.delete as.name

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
        all_settings[as.name] = settings
        all_settings.delete as.id

        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end
end