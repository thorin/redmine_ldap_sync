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
module LdapSync::DryRun::User

  module ClassMethods
    def create(attributes)
      user = User.new(attributes)
      yield user if block_given?
      user
    end
  end

  module InstanceMethods
    def lock!();end

    def activate!(); end

    def update_attributes(attrs = {}); end

    def save(*args); end
  end

  def self.included(receiver)
    receiver.extend(ClassMethods)
    receiver.send(:include, InstanceMethods)

    receiver.instance_eval do
      has_and_belongs_to_many :groups do
        def <<(groups)
          puts "   !! Added to groups '#{groups.map(&:lastname).join("', '")}'" unless groups.empty?
        end

        def delete(*groups)
          puts "   !! Removed from groups '#{groups.map(&:lastname).join("', '")}'" unless groups.empty?
        end
      end

      remove_method :lock!, :activate!
    end

  end
end