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
module LdapSync::EntityManager

  private
    def get_user_fields(username, user_data=nil, options={})
      if options.try(:fetch, :include_required)
        custom_fields = user_required_custom_fields.map {|cf| cf.id.to_s }
        fields_to_sync = User::STANDARD_FIELDS + custom_fields
        ldap_attrs_to_sync = setting.user_ldap_attrs_to_sync(fields_to_sync)
      else
        ldap_attrs_to_sync = setting.user_ldap_attrs_to_sync
        fields_to_sync = setting.user_fields_to_sync
      end

      user_data ||= with_ldap_connection do |ldap|
        find_user(ldap, username, ldap_attrs_to_sync)
      end
      return {} if user_data.nil?

      user_fields = user_data.inject({}) do |fields, (attr, value)|
        f = setting.user_field(attr)
        if f && fields_to_sync.include?(f)
          fields[f] = value.first unless value.nil? || value.first.blank?
        end
        fields
      end

      user_required_custom_fields.each do |cf|
        if user_fields[cf.id.to_s].blank?
          user_fields[cf.id.to_s] = cf.default_value
        end
      end

      user_fields
    end

    def get_group_fields(groupname, group_data = nil)
      group_data ||= with_ldap_connection do |ldap|
        find_group(ldap, groupname, [n(:groupname), *setting.group_ldap_attrs_to_sync])
      end || {}

      group_fields = group_data.inject({}) do |fields, (attr, value)|
        f = setting.group_field(attr)
        if f && setting.group_fields_to_sync.include?(f)
          fields[f] = value.first unless value.nil? || value.first.blank?
        end
        fields
      end

      group_required_custom_fields.each do |cf|
        if group_fields[cf.id.to_s].blank?
          group_fields[cf.id.to_s] = cf.default_value
        end
      end

      group_fields
    end

    def user_required_custom_fields
      @user_required_custom_fields ||= UserCustomField.select(&:is_required)
    end

    def group_required_custom_fields
      @group_required_custom_fields ||= GroupCustomField.select(&:is_required)
    end

    def ldap_users
      return @ldap_users if @ldap_users

      with_ldap_connection do |ldap|
        changes = { :enabled => SortedSet.new, :disabled => SortedSet.new }

        unless setting.has_account_flags?
          changes[:enabled] += find_all_users(ldap, n(:login)).map(&:first)
        else
          find_all_users(ldap, ns(:login, :account_flags)) do |entry|
            if account_disabled?(entry[n(:account_flags)].first)
              changes[:disabled] << entry[n(:login)].first
            else
              changes[:enabled] << entry[n(:login)].first
            end
          end
        end

        changes[:enabled].delete(nil)
        changes[:disabled].delete(nil)

        users_on_local = self.users.active.map {|u| u.login.downcase }
        users_on_ldap = changes.values.sum.map(&:downcase)
        deleted_users = users_on_local - users_on_ldap
        changes[:disabled] += deleted_users

        trace "-- Found #{changes[:enabled].size} users active" \
          ", #{changes[:disabled].size - deleted_users.size} locked" \
          " and #{deleted_users.size} deleted on ldap"

        # Sort users, clearer for the rake task
        # TODO user Array instead of Set at the beginning ?
        changes[:enabled] = changes[:enabled].to_a.sort
        changes[:disabled] = changes[:disabled].to_a.sort

        @ldap_users = changes
      end

    end

    def groups_changes(user)
      return unless setting.active?
      changes = { :added => SortedSet.new, :deleted => SortedSet.new }

      user_groups = user.groups.map {|g| g.name.downcase }
      groupname_regexp = setting.groupname_regexp

      with_ldap_connection do |ldap|
        # Find which of the user's current groups are in ldap
        filtered_groups = user_groups.select {|g| groupname_regexp =~ g }
        names_filter    = filtered_groups.map {|g| Net::LDAP::Filter.eq( setting.groupname, g )}.reduce(:|)
        find_all_groups(ldap, names_filter, n(:groupname)) do |group|
          changes[:deleted] << group.first
        end if names_filter

        changes[:added] += get_primary_group(ldap, user) if setting.has_primary_group?

        case setting.group_membership
        when 'on_groups'
          # Find user's memberid
          memberid = user.login
          if setting.user_memberid != setting.login
            entry = find_user(ldap, user.login, ns(:user_memberid)) and
              memberid = entry[n(:user_memberid)].first and
              user_dn = entry[:dn].first
          end

          if setting.user_memberid == setting.login || entry.present?
            # Find the static groups to which the user belongs to (groupOfNames)
            member_filter = Net::LDAP::Filter.eq( setting.member, memberid )
            find_all_groups(ldap, member_filter, n(:groupname)) do |group|
              changes[:added] << group.first
            end if memberid
          end

        else # 'on_members'
          entry = find_user(ldap, user.login, ns(:user_groups))
          if entry.present?
            groups = entry[n(:user_groups)]
            user_dn = entry[:dn].first

            names_filter = groups.map{|g| Net::LDAP::Filter.eq( setting.groupid, g )}.reduce(:|)
            find_all_groups(ldap, names_filter, n(:groupname)) do |group|
              changes[:added] << group.first
            end if names_filter
          end
        end

        changes[:added] = changes[:added].inject(Set.new) do |closure, group|
          closure + closure_cache.fetch(group) do
            get_group_closure(ldap, group).select {|g| groupname_regexp =~ g }
          end
        end if setting.nested_groups_enabled?

        # Find the dynamic groups to which the user belongs to (groupOfURLs)
        if setting.sync_dyngroups?
          user_dn ||= find_user(ldap, user.login, :dn).try(:first)
          changes[:added] += get_dynamic_groups(user_dn) unless user_dn.nil?
        end
      end

      changes[:added].delete_if {|group| groupname_regexp !~ group }
      changes[:deleted] -= changes[:added]
      changes[:added].delete_if {|group| user_groups.include?(group.downcase) }

      changes
    ensure
      reset_parents_cache! unless running_rake?
    end

    def get_primary_group(ldap, user)
      primary_group_id = find_user(ldap, user.login, n(:primary_group)).try(:first)
      return [] if primary_group_id.nil?

      # Map GID to group name
      gid_filter = Net::LDAP::Filter.eq( setting.primary_group, primary_group_id )
      find_all_groups(ldap, gid_filter, n(:groupname)).first || []
    end

    def get_dynamic_groups(user_dn)
      reload_dyngroups! unless dyngroups_fresh?

      dyngroups_cache.fetch(member_key(user_dn)) || []
    end

    def reload_dyngroups!
      with_ldap_connection {|c| find_all_dyngroups(c, :update_cache => true) }
    end

    def get_group_closure(ldap, group, closure=Set.new)
      groupname = group.is_a?(String) ? group : group[n(:groupname)].first
      parent_groups = parents_cache.fetch(groupname) do
        case setting.nested_groups
        when 'on_members'
          group = find_group(ldap, groupname, ns(:groupname, :group_memberid, :parent_group)) if group.is_a? String

          if group[n(:parent_group)].present?
            groups_filter = group[n(:parent_group)].map{|g| Net::LDAP::Filter.eq( setting.group_parentid, g )}.reduce(:|)
            cacheable_ber find_all_groups(ldap, groups_filter, ns(:groupname, :group_memberid, :parent_group))
          else
            Array.new
          end
        else # 'on_parents'
          group = find_group(ldap, groupname, ns(:groupname, :group_memberid)) if group.is_a? String

          member_filter = Net::LDAP::Filter.eq( setting.member_group, group[n(:group_memberid)].first )
          cacheable_ber find_all_groups(ldap, member_filter, ns(:groupname, :group_memberid)).map
        end
      end

      closure << groupname
      parent_groups.each_with_object(closure) do |group, closure|
        closure += get_group_closure(ldap, group, closure) unless closure.include? group[n(:groupname)].first
      end
    end

    def find_group(ldap, group_name, attrs, &block)
      extra_filter = Net::LDAP::Filter.eq( setting.groupname, group_name )
      result = find_all_groups(ldap, extra_filter, attrs, &block)
      result.first if !block_given? && result.present?
    end

    def find_all_groups(ldap, extra_filter, attrs, options = {}, &block)
      object_class = options[:class] || setting.class_group
      groups_base_dn = setting.has_groups_base_dn? ? setting.groups_base_dn : nil
      group_filter = Net::LDAP::Filter.eq( :objectclass, object_class )
      group_filter &= Net::LDAP::Filter.construct( setting.group_search_filter ) if setting.group_search_filter.present?
      group_filter &= extra_filter if extra_filter

      ldap_search(ldap, {:base =>  groups_base_dn,
                   :filter => group_filter,
                   :attributes => attrs,
                   :return_result => block_given? ? false : true},
                  &block)
    end

    def find_all_dyngroups(ldap, options = {})
      options = options.reverse_merge(:attrs => [:cn, :member], :update_cache => false)
      users_base_dn = setting.base_dn.downcase

      dyngroups = Hash.new{|h,k| h[k] = []}

      find_all_groups(ldap, nil, options[:attrs], :class => 'groupOfURLs') do |entry|
        yield entry if block_given?

        if options[:update_cache]
          entry[:member].each do |member|
            next unless (member.downcase.ends_with?(users_base_dn))

            dyngroups[member_key(member)] << entry[:cn].first
          end
        end
      end

      update_dyngroups_cache!(dyngroups) if options[:update_cache]
    end

    def find_user(ldap, login, attrs, &block)
      user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
      user_filter &= setting.ldap_filter if setting.filter.present?
      login_filter = Net::LDAP::Filter.eq( setting.login, login )

      result = ldap_search(ldap, {:base => setting.base_dn,
                            :filter => user_filter & login_filter,
                            :attributes => attrs,
                            :return_result => block_given? ? false : true},
                           &block)
      result.first if !block_given? && result.present?
    end

    def find_all_users(ldap, attrs, &block)
      user_filter = Net::LDAP::Filter.eq( :objectclass, setting.class_user )
      user_filter &= setting.ldap_filter if setting.filter.present?

      ldap_search(ldap, {:base => setting.base_dn,
                   :filter => user_filter,
                   :scope => (Net::LDAP::SearchScope_SingleLevel if setting.users_search_onelevel?),
                   :attributes => attrs,
                   :return_result => block_given? ? false : true},
                  &block)
    end

    def ldap_search(ldap, options, &block)
      attrs = options[:attributes]

      return ldap.search(options, &block) if attrs.is_a?(Array) || attrs.nil?

      options[:attributes] = [attrs]

      block = Proc.new {|e| yield e[attrs] } if block_given?
      result = ldap.search(options, &block) or fail
      result.map {|e| e[attrs] } unless block_given? || result.nil?
    rescue
      os = ldap.get_operation_result
      raise Net::LDAP::LdapError, "LDAP Error(#{os.code}): #{os.message}"
    end

    def n(field)
      setting.send(field)
    end

    def ns(*args)
      setting.ldap_attributes(*args)
    end

    def member_key(member)
      member[0...-setting.base_dn.length-1]
    end

    def account_disabled?(flags)
      return false if flags.blank?

      !!setting.account_disabled_proc.try(:call, flags)
    end

    def connect_as_user?; setting.account.include?('$login'); end

    def cacheable_ber(result)
      result.map do |h|
        h = Hash[ h.map {|k,v| [k, v.to_a] } ]
        HashWithIndifferentAccess.new( h )
      end
    end

    def with_ldap_connection(login = nil, password = nil)
      thread = Thread.current

      return yield thread[:local_ldap_con] if thread[:local_ldap_con].present?

      ldap_con = if setting.account && setting.account.include?('$login')
        initialize_ldap_con(setting.account.sub('$login', Net::LDAP::DN.escape(login)), password)
      else
        initialize_ldap_con(setting.account, setting.account_password)
      end

      ldap_con.open do |ldap|
        begin
          yield thread[:local_ldap_con] = ldap
        ensure
          thread[:local_ldap_con] = nil
        end
      end
    end

    def info(msg = ""); trace msg, :level => :change; end
    def change(obj = "", msg = ""); trace msg, :level => :change, :obj => obj; end
    def error(msg); trace msg, :level => :error; end
end
