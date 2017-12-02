class UpdateUserGroupFields < ActiveRecord::Migration[4.2]

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:group_fields_to_sync] ||= []
        settings[:user_fields_to_sync] ||= []
        settings[:user_ldap_attrs] ||= {}
        settings[:group_ldap_attrs] ||= {}
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end

  def self.down
    # nothing to do
  end
end