class UpdateAttributesToSync < ActiveRecord::Migration[4.2]

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings.delete(:sync_user_attributes)
        settings[:user_fields_to_sync] = settings[:attributes_to_sync]
        settings.delete(:attributes_to_sync)
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end

  def self.down
    # nothing to do
  end
end
