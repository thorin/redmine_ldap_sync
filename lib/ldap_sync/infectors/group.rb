module LdapSync::Infectors::Group

  module InstanceMethods
    def set_default_values
      custom_fields = GroupCustomField.where("default_value is not null")

      self.custom_field_values = custom_fields.each_with_object({}) do |f, h|
        h[f.id] = f.default_value
      end
    end

    def synced_fields=(attrs)
      self.custom_field_values = attrs
    end
  end

  def self.included(receiver)
    receiver.send(:include, InstanceMethods)
  end

end