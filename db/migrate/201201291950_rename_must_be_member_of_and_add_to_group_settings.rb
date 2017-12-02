class RenameMustBeMemberOfAndAddToGroupSettings < ActiveRecord::Migration[4.2]

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:required_group] = settings[:must_be_member_of]
        settings[:fixed_group] = settings[:add_to_group]
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end

  def self.down
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:must_be_member_of] = settings[:required_group]
        settings[:add_to_group] = settings[:fixed_group]
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end
end
