class ChangeSettingsName < ActiveRecord::Migration

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:add_to_group] = settings.delete(:domain_group)
        settings[:groupname_pattern] = settings.delete(:groupname_filter)
        settings[:create_groups] = true
        settings[:create_users] = true
        settings[:sync_user_attributes] = false
        settings[:attr_member] = 'member'
        settings[:class_group] = 'group'
        settings[:class_user] = 'user'
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end

  def self.down
    remove_column :issues, :is_private
  end
end
