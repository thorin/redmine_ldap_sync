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
module LdapSync::Infectors::AuthSourceLdap

  module InstanceMethods
    include LdapSync::EntityManager

    public
    def sync_groups
      if connect_as_user?
        trace "   -> Cannot synchronize: no account/password configured"; return
      end
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"; return
      end
      unless setting.sync_group_fields? || setting.create_groups? || setting.sync_dyngroups?
        trace "   -> No attributes to sync: skipping"; return
      end

      with_ldap_connection do |ldap|
        trace "** Synchronizing non-dynamic groups"
        attrs = [n(:groupname), *setting.group_ldap_attrs_to_sync]
        find_all_groups(ldap, nil, attrs) do |entry|
          create_and_sync_group(entry, n(:groupname))
        end if setting.sync_group_fields? || setting.create_groups?

        return unless setting.sync_dyngroups?

        trace "** Synchronizing dynamic groups"
        find_all_dyngroups(ldap,
          :attrs => [:cn, :member, *setting.group_ldap_attrs_to_sync],
          :update_cache => !dyngroups_fresh?) do |entry|
          create_and_sync_group(entry, :cn)
        end
      end
    end

    def sync_users
      if connect_as_user?
        trace "   -> Cannot synchronize: no account/password configured"; return
      end
      unless setting.active?
        trace "   -> Ldap sync is disabled: skipping"; return
      end

      @closure_cache = new_memory_cache if setting.nested_groups_enabled?

      with_ldap_connection do |_|
        ldap_users[:disabled].each do |login|
          user = self.users.where("LOWER(login) = ?", login.downcase).first

          if user.try(:active?)
            if user.lock!
              change user.login, "-- Locked active user '#{user.login}'"
            else
              change user.login, "-- Failed to lock active user '#{user.login}'"
            end
          elsif user.present?
            trace "-- Not locking locked user '#{user.login}'"
          end
        end

        ldap_users[:enabled].each do |login|
          user, is_new_user = find_or_create_user(login)
          sync_user(user, is_new_user) if user.present?
        end
      end

      update_closure_cache! if setting.nested_groups_enabled?
    end

    def sync_user(user, is_new_user = false, options = {})
      with_ldap_connection(options[:login], options[:password]) do |ldap|
        if user.locked? && !(activate_users? || setting.has_required_group?)
          trace "-- Not #{is_new_user ? 'creating': 'updating'} locked user '#{user.login}'"; return
        else
          trace "-- #{is_new_user ? 'Creating' : 'Updating'} user '#{user.login}'...",
            :level => is_new_user ? :change : :debug,
            :obj => user.login
        end

        user_data, flags = if options[:try_to_login] && setting.has_account_flags? && setting.sync_fields_on_login?
          user_data = find_user(ldap, user.login, setting.user_ldap_attrs_to_sync + ns(:account_flags))
          [user_data, user_data[n(:account_flags)].first]
        end

        sync_user_groups(user) unless options[:try_to_login] && !setting.sync_groups_on_login?
        sync_user_status(user, flags)

        return if user.locked?

        sync_admin_privilege(user)
        sync_user_fields(user, user_data) unless is_new_user || (options[:try_to_login] && !setting.sync_fields_on_login?)
      end
    end

    def locked_on_ldap?(user, options = {})
      with_ldap_connection(options[:login], options[:password]) do |ldap|
        locked = if setting.has_account_flags? && setting.sync_fields_on_login?
          flags = find_user(ldap, user.login, n(:account_flags)).first
          account_disabled?(flags)
        end

        locked ||= if setting.has_required_group? && setting.sync_groups_on_login?
          user_groups = groups_changes(user)[:added].map(&:downcase)
          !user_groups.include?(setting.required_group.downcase)
        end

        locked || false
      end
    end

    private
      def create_and_sync_group(group_data, attr_groupname)
        groupname = group_data[attr_groupname].first
        return unless setting.groupname_regexp =~ groupname

        group, is_new_group = find_or_create_group(groupname, group_data)
        return if group.nil?

        trace "-- #{is_new_group ? 'Creating' : 'Updating'} group '#{group.name}'...",
          :level => is_new_group ? :change : :debug,
          :obj => group.name
        sync_group_fields(group, group_data) unless is_new_group

        group
      end

      def sync_user_groups(user)
        return unless setting.active?

        if setting.has_fixed_group? && !user.member_of_group?(setting.fixed_group)
          user.add_to_fixed_group
        end

        changes = groups_changes(user)
        added = changes[:added].map {|g| find_or_create_group(g).first }.compact
        user.groups << added if added.present?

        deleted_groups = changes[:deleted].map(&:downcase)
        deleted = deleted_groups.any? ? ::Group.where("LOWER(lastname) in (?)", deleted_groups).all : []
        user.groups.delete(*deleted) unless deleted.empty?

        trace_groups_changes_summary(user, changes, added, deleted)
      end

      def sync_user_fields(user, user_data = nil)
        return unless setting.active? && setting.sync_user_fields?

        user.synced_fields = get_user_fields(user.login, user_data)
        if user.save
          user
        else
          error "Could not sync user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
        end
      end

      def sync_user_status(user, flags = nil)
        if flags && account_disabled?(flags)
          user.lock!
          change user.login, "   -> locked: user disabled on ldap with flags '#{flags}'"
        elsif setting.has_required_group?
          if user.member_of_group?(setting.required_group)
            if user.locked?
              user.activate!
              change user.login, "   -> activated: member of group '#{setting.required_group}'"
            end
          elsif user.active?
            user.lock!
            change user.login, "   -> locked: not member of group '#{setting.required_group}'"
          end
        elsif activate_users? && user.locked?
          user.activate!
          change user.login, "   -> activated: ACTIVATE_USERS flag is on"
        end
      end

      def sync_admin_privilege(user)
        return unless setting.has_admin_group?

        if user.member_of_group?(setting.admin_group)
          unless user.admin?
            user.set_admin!
            change user.login, "   -> granted admin privileges: member of group '#{setting.admin_group}'"
          end
        else
          if user.admin?
            user.unset_admin!
            change user.login, "   -> revoked admin privileges: not member of group '#{setting.admin_group}'"
          end
        end
      end

      def sync_group_fields(group, group_data)
        group.synced_fields = get_group_fields(group.name, group_data)

        if group.save
          group
        else
          change group.name, "-- Could not sync group '#{group.lastname}': \"#{group.errors.full_messages.join('", "')}\""; nil
        end
      end

      def find_or_create_group(groupname, group_data = nil)
        group = ::Group.where("LOWER(lastname) = ?", groupname.downcase).first
        return group, false unless group.nil? && setting.create_groups?

        group = ::Group.new(:lastname => groupname, :auth_source_id => self.id) do |g|
          g.set_default_values
          g.synced_fields = get_group_fields(groupname, group_data)
        end

        if group.save
          return group, true
        else
          change group.name, "Could not create group '#{groupname}': \"#{group.errors.full_messages.join('", "')}\""
          return nil, false
        end
      end

      def find_or_create_user(username)
        user = ::User.where("LOWER(#{User.table_name}.login) = ?", username.downcase).includes(:groups).first
        if user.present? && user.auth_source_id != self.id
          trace "-- Skipping user '#{user.login}': it already exists on a different auth_source"
          return nil, false
        end
        return user unless user.nil? && setting.create_users?

        user = ::User.new do |u|
          u.login = username
          u.set_default_values
          u.synced_fields = get_user_fields(username)
          u.auth_source_id = self.id
        end

        if user.save
          return user, true
        else
          change user.login,  "-- Could not create user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""; nil
        end
      end

      def new_memory_cache
        cache = Hash.new
        def cache.fetch(key, &block)
          self[key] = super(key, &block)
        end
        cache
      end

      def parents_cache
        @parents_cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
      end

      def reset_parents_cache!
        @parents_cache.clear unless @parents_cache.nil?
      end

      def dyngroups_fresh?
        if running_rake?
          !dyngroups_updated?
        else
          opts = {}
          if setting.dyngroups_enabled_with_ttl?
            # We do a TTL bump here to reduce the load on LDAP
            opts[:race_condition_ttl] = 5.minutes
            opts[:expires_in] = setting.dyngroups_cache_ttl.to_f.minutes
          end

          expired = false
          dyngroups_cache.fetch(:cache_control, opts) { expired = true }
          !expired
        end
      end

      def cache_root
        root_path = Rails.root.join("tmp/ldap_cache/#{self.id}")
        FileUtils.mkdir_p root_path unless File.exists? root_path

        root_path
      end

      def closure_cache
        @closure_cache ||= ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/nested_groups")
      end

      def dyngroups_cache
        @dyngroups_cache ||= ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/dyngroups")
      end

      def update_closure_cache!
        disk_cache = ActiveSupport::Cache.lookup_store(:file_store, "#{cache_root}/nested_groups")
        mem_cache = @closure_cache

        # Match all the entries we want to delete
        disk_cache.delete_unless {|k| mem_cache.has_key?(k) }
        mem_cache.each {|k, v| disk_cache.write(k, v) }
      end

      def update_dyngroups_cache!(mem_cache)
        opts = {}
        if setting.dyngroups_enabled_with_ttl?
          opts[:race_condition_ttl] = 5.minutes
          opts[:expires_in] = setting.dyngroups_cache_ttl.to_f.minutes
        end
        dyngroups_cache.write(:cache_control, true, opts)

        dyngroups_cache.delete_unless {|k| k == 'cache_control' || mem_cache.has_key?(k) }
        mem_cache.each {|k, v| dyngroups_cache.write(k, v) }

        self.dyngroups_updated = true
      end

      def setting
        return @setting if @setting

        @setting = LdapSetting.find_by_auth_source_ldap_id(self.id)
      end

      def pluralize(n, word)
        word.present? ? "#{n} #{word}#{'s' if n != 1}" : n.to_s
      end

      def trace_groups_changes_summary(user, groups, added, deleted)
        return unless running_rake?

        a = added.size; d = deleted.size; nc = groups[:added].size - a
        chg = []
        chg << "#{pluralize(a, 'group')} added" if a > 0
        chg << "#{pluralize(d, a == 0 ? 'group' : nil)} deleted" if d > 0
        chg << "#{pluralize(nc, a + d == 0 ? 'group' : nil)} not created" if nc > 0

        msg = if chg.size == 1
          "   -> #{chg[0]}"
        elsif chg.size > 1
          "   -> #{[chg[0...-1].join(', '), chg[-1]].join(' and ')}"
        end

        level = a > 0 || d > 0 ? :change : :debug
        trace msg, :level => level, :obj => user.login
      end

      def trace(msg, options = {})
        return if trace_level == :silent || msg.nil?
        logger.error msg if options[:level] == :error && !running_rake?

        return if !running_rake?

        options.reverse_merge!(:level => :debug)

        case options[:level]
        when :error;  puts "-- #{msg}"
        when :debug;  puts msg unless [:change, :error].include? trace_level
        when :info;   puts msg unless [:error].include? trace_level
        when :change
          if trace_level == :change && !options[:obj].nil?
            obj = options[:obj]
            trace_msg = msg.gsub(/^.*?(\w)/, '\1').
                gsub('...', '').
                gsub(/ '#{obj}'/, '').
                downcase
            puts "[#{obj}] #{trace_msg}"
          else
            puts msg unless [:error].include? trace_level
          end
        end
      end

      def dyngroups_updated?; self.dyngroups_updated; end
      def activate_users?; self.activate_users; end
      def running_rake?; self.running_rake; end
  end

  module ClassMethods
    def activate_users!
      self.activate_users = true
    end

    def running_rake!
      self.running_rake = true
    end
  end

  def self.included(receiver)
    receiver.extend(ClassMethods)
    receiver.send(:include, InstanceMethods)

    receiver.instance_eval do
      delegate :has_fixed_group?, :fixed_group, :sync_on_login?, :to => :setting, :allow_nil => true
      cattr_accessor :activate_users, :running_rake, :dyngroups_updated
      cattr_accessor :trace_level do
        :debug
      end
      unloadable
    end
  end
end