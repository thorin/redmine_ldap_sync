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
class LdapTest
  include Redmine::I18n
  include LdapSync::EntityManager
  include ActiveModel::Conversion
  include ActiveModel::Validations
  extend ActiveModel::Naming

  attr_accessor :setting, :bind_user, :bind_password, :test_users, :test_groups, :messages, :user_attrs, :group_attrs, :users_at_ldap, :groups_at_ldap, :non_dynamic_groups, :dynamic_groups, :users_locked_by_group, :admin_users, :user_changes

  delegate :auth_source_ldap, :to => :setting
  delegate :users, :to => :auth_source_ldap

  validates_presence_of :bind_user, :bind_password, :if => :connect_as_user?

  def initialize(setting)
    setting.active = true

    @setting = setting
    @messages = ''
    @user_changes = {:enabled => [], :locked => [], :deleted => []}
    @users_at_ldap = {}
    @groups_at_ldap = {}
    @non_dynamic_groups = []
    @dynamic_groups = {}
    @users_locked_by_group = []
    @admin_users = []
  end

  def initialize_ldap_con(login, password)
    auth_source_ldap.send(:initialize_ldap_con, login, password)
  end

  def run_with_users_and_groups(users, groups)
    with_ldap_connection(@bind_user, @bind_password) do |ldap|
      @user_changes = ldap_users
      users.each do |login|
        user_data = find_user(ldap, login, nil)
        if user_data
          @user_attrs ||= user_data
          users_at_ldap[login] = {
            :fields => get_user_fields(login, user_data, :include_required => true),
            :groups => groups_changes(User.new {|u| u.login = login })
          }
        else
          users_at_ldap[login] = :not_found
        end
      end

      user_changes[:enabled].each do |login|
        group_changes = groups_changes(User.new {|u| u.login = login })
        enabled_groups = group_changes[:added].map(&:downcase)

        if setting.has_admin_group?
          admin_users << login if enabled_groups.include? setting.admin_group.downcase
        end

        if setting.has_required_group?
          users_locked_by_group << login unless enabled_groups.include? setting.required_group.downcase
        end
      end if setting.has_admin_group? || setting.has_required_group?

      groups.each do |name|
        group_data = find_group(ldap, name, nil)
        if group_data
          @group_attrs ||= group_data
          groups_at_ldap[name] = {
            :fields => get_group_fields(name, group_data)
          }
        else
          groups_at_ldap[name] = :not_found
        end
      end

      find_all_groups(ldap, nil, n(:groupname)) do |entry|
        if !setting.has_groupname_pattern? || entry.first =~ /#{setting.groupname_pattern}/
          non_dynamic_groups << entry.first
        end
      end
      if setting.sync_dyngroups?
        find_all_dyngroups(ldap, :update_cache => true)
        dynamic_groups.reject! {|(k, v)| k !~ /#{setting.groupname_pattern}/ } if setting.has_groupname_pattern?
      end
    end
  rescue Exception => e
    error(e.message + e.backtrace.join("\n  "))
  end

  def self.human_attribute_name(attr, *args)
    attr = attr.to_s.sub(/_id$/, '')

    l("field_#{name.underscore.gsub('/', '_')}_#{attr}", :default => ["field_#{attr}".to_sym, attr])
  end

  def persisted?; true; end

  private
    def update_dyngroups_cache!(mem_cache)
      @dynamic_groups = Hash.new{|h,k| h[k] = Set.new}
      mem_cache.each do |(login, groups)|
        dyngroups_cache.write(login, groups)

        groups.each {|group| @dynamic_groups[group] << login }
      end
    end

    def closure_cache
      @closure_cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
    end

    def dyngroups_cache
      @dyngroups_cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
    end

    def parents_cache
      @parents_cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
    end

    def trace(msg = "", options = {})
      @messages += "#{msg}\n" if msg
    end

    def running_rake?; true; end
    def dyngroups_fresh?; false; end
end
