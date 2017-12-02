class RemoveAttrPrefixSettings < ActiveRecord::Migration[4.2]

  def self.up
    all_settings = Setting.plugin_redmine_ldap_sync
    return unless all_settings

    AuthSourceLdap.all.each do |as|
      settings = all_settings[as.name]

      say_with_time "Updating settings for '#{as.name}'" do
        settings[:groupname] = settings[:attr_groupname]
        settings[:member] = settings[:attr_member]
        settings[:user_memberid] = settings[:attr_user_memberid]
        settings[:user_groups] = settings[:attr_user_groups]
        settings[:groupid] = settings[:attr_groupid]
        settings[:member_group] = settings[:attr_member_group]
        settings[:goup_memberid] = settings[:attr_group_memberid]
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
        settings[:attr_groupname] = settings[:groupname]
        settings[:attr_member] = settings[:member]
        settings[:attr_user_memberid] = settings[:user_memberid]
        settings[:attr_user_groups] = settings[:user_groups]
        settings[:attr_groupid]= settings[:groupid]
        settings[:attr_member_group] = settings[:member_group]
        settings[:attr_group_memberid] = settings[:goup_memberid]
        Setting.plugin_redmine_ldap_sync = all_settings
      end if settings
    end
  end
end
