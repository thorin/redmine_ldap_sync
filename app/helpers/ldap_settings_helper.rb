module LdapSettingsHelper
  def config_css_classes(config)
    "ldap_setting #{config.active? ? 'enabled' : 'disabled' }"
  end

  def change_status_link(config)
    if config.active?
      link_to 'Disable', disable_ldap_setting_path(config), method: :put, :class => 'icon icon-disable'
    else
      link_to 'Enable', enable_ldap_setting_path(config), method: :put, :class => 'icon icon-enable'
    end
  end

  def ldap_setting_tabs(form)
    [
      {:name => 'LdapSettings', :partial => 'ldap_settings', :label => :label_ldap_settings, :form => form},
      {:name => 'SynchronizationActions', :partial => 'synchronization_actions', :label => :label_synchronization_actions, :form => form},
      {:name => 'Test', :partial => 'test', :label => :label_test, :form => form}
    ]
  end

  def options_for_nested_groups
    [
      [l(:option_disabled_nested_groups), ''],
      [l(:option_nested_groups_on_parents), :on_parents],
      [l(:option_nested_groups_on_members), :on_members]
    ]
  end

  def options_for_group_membeship
    [
      [l(:option_group_membership_on_groups), :on_groups],
      [l(:option_group_membership_on_members), :on_members]
    ]
  end

  def multiselect(object, method, choices, options={})
    values = object.send(method)
    values = [] unless values.is_a?(Array)
    field_name = "#{object.class.name.underscore}[#{method}][]"

    content_tag("label", l(options[:label] || "field_" + method.to_s)) +
      hidden_field_tag(field_name, '').html_safe +
      choices.collect do |choice|
        text, value = (choice.is_a?(Array) ? choice : [l("field_#{choice}"), choice])
        content_tag("label",
          check_box_tag(field_name, value, values.include?(value), :id => nil) + text.to_s,
          :class => (options[:inline] ? 'inline' : 'block')
         )
      end.join.html_safe
  end

  def options_for_base_settings
    options = [[l(:option_custom), '']]
    options += base_settings.collect {|k, h| [h['name'], k] }.sort
    options_for_select(options, current_base)
  end

  def baseable_fields
    [*LdapSetting::LDAP_ATTRIBUTES, *LdapSetting::CLASS_NAMES, *LdapSetting::COMBOS, 'account_disabled_test']
  end

  def base_settings
    @base_settings if @base_settings

    config_dir = File.join(Redmine::Plugin.find(:redmine_ldap_sync).directory, 'config')
    default = baseable_fields.inject({}) {|h, k| h[k] = ''; h }
    @base_settings = YAML::load_file(File.join(config_dir, 'base_settings.yml'))
    @base_settings.each {|k,h| h.reverse_merge!(default) }
  end

  private
    def current_base
      base_settings.each do |key, hash|
        return key if hash.slice(*baseable_fields).all? {|k,v| @ldap_setting.send(k) == (v || '') }
      end
      ''
    end
end
