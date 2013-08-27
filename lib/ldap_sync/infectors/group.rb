# encoding: utf-8
# Copyright (C) 2011-2013  The Redmine LDAP Sync Authors
#
# This file is part of Redmine LDAP Sync.
#
# Redmine LDAP Sync is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Redmine LDAP Sync is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Redmine LDAP Sync.  If not, see <http://www.gnu.org/licenses/>.
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