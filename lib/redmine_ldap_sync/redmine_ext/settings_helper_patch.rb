module RedmineLdapSync
  module RedmineExt
    module SettingsHelperPatch
      def self.included(base)
        base.class_eval do
          
          def ldap_multiselect(ldap_name, setting, choices, options={})
            setting_values = @settings[ldap_name]? @settings[ldap_name][setting]: []
            setting_values = [] unless setting_values.is_a?(Array)

            ldap_label(setting, options) +
              choices.collect do |choice|
                text, value = (choice.is_a?(Array) ? choice : [l("field_#{@plugin.id}_#{choice}"), choice])
                content_tag(
                  'label',
                  check_box_tag(
                     "settings[#{ldap_name}][#{setting}][]",
                     value,
                     setting_values.include?(value)
                   ) + text.to_s,
                  :class => 'block'
                 )
              end.join
          end

          def ldap_label(setting, options={})
            label = options.delete(:label)
            return '' if label == false

            label_text = l(label || "field_#{@plugin.id}_#{setting}") + (options.delete(:required) ? content_tag("span", " *", :class => "required") : "")
            content_tag("label", label_text)
          end

          def ldap_text_field(ldap_name, setting, options={})
            default = options.delete(:default)
            ldap_settings = @settings[ldap_name]
            ldap_label(setting, options) +
              text_field_tag("settings[#{ldap_name}][#{setting}]", (ldap_settings ? ldap_settings[setting] : default), options)
          end

          def ldap_check_box(ldap_name, setting, options={})
            default = options.delete(:default)
            ldap_settings = @settings[ldap_name]
            ldap_label(setting, options) +
              check_box_tag("settings[#{ldap_name}][#{setting}]", 'yes', (ldap_settings ? ldap_settings[setting] : default), options)
          end

        end
      end
    end
  end
end
