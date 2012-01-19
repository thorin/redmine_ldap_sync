module RedmineLdapSync
  module RedmineExt
    module AuthSourceLdapPatch
      def self.included(base)
        base.class_eval do

        public

          def cache_duration
            if @cache_duration
              @cache_duration
            else
              120
            end
          end

          def cache_duration=(cache_duration)
            @cache_duration = cache_duration
          end

          def sync_groups(user)
            return unless ldapsync_active?

            puts "   ==>openning connection for #{self.account.present? ? self.account : 'anonymous'}"
            ldap_con = initialize_ldap_con(self.account, self.account_password)

            ldap_con.open do |new_ldap|
              sync_groups_con(user, new_ldap)
            end
          end

          def sync_groups_con(user, ldap)
            return unless ldapsync_active?

            if add_to_group.present? && !user.groups.detect { |g| g.to_s == add_to_group }
              if settings[:dry_run].blank?
                logger.debug "==>dynamic default group add '#{add_to_group}' for #{user.login}" if logger && logger.debug?
                user.add_to_auth_source_group
              else
                logger.debug "==>dry-run : NO dynamic default group add '#{add_to_group}' for #{user.login}" if logger && logger.debug?
              end
            end

            changes = nil

            changes = groups_changes_con(user, ldap)

            changes[:added].each do |groupname|
              group = Group.find_by_lastname(groupname)
              if group.nil?
                if create_groups?
                  if settings[:dry_run].blank?
                    logger.debug "==>dynamic group creation '#{groupname}' for #{user.login}" if logger && logger.debug?
                    group = Group.create_by_lastname(groupname, :auth_source_id => self.id)
                  else
                    logger.debug "==>dry-run : NO dynamic group creation '#{groupname}' for #{user.login}" if logger && logger.debug?
                  end
                end
              end

              group.users << user if group && (!settings[:dry_run].present?)
            end

            changes[:deleted].each do |groupname|
              next unless group = user.groups.detect { |g| g.to_s == groupname }

              if settings[:dry_run].blank?
                logger.debug "==>dynamic group remove #'{groupname}' for #{user.login}" if logger && logger.debug?
                group.users.delete(user) && (!settings[:dry_run].present?)
              else
                logger.debug "==>dry-run : NO dynamic group remove #'{groupname}' for #{user.login}" if logger && logger.debug?
              end
            end

            changes
          end

          def sync_users(dry_run=false)
            return unless ldapsync_active?

            if dry_run
              settings[:dry_run] = true
            end

            ldap_con = initialize_ldap_con(self.account, self.account_password)

            ldap_con.open do |ldap|
              # Lock disabled Users
              _ldap_users = ldap_users_con(ldap_con)
              _ldap_users[:disabled].each do |login|
                user = User.find_by_login_and_auth_source_id(login, self.id)

                if user.present? && user.active?
                  if !settings[:dry_run].present?
                    user.lock!
                  end
                  puts "-- Locked user '#{user.login}'"
                end
              end

              groupname = settings[:must_be_member_of]

              _ldap_users[:enabled].each do |login|
                # Create new users
                user_is_fresh = false
                user = User.find_by_login(login)
                user = User.create do |u|
                  u.login = login
                  u.attributes = get_user_dn_con(login, ldap_con).except(:dn)
                  u.language = Setting.default_language
                  user_is_fresh = true
                end if (!settings[:dry_run].present?) && user.nil? && create_users?

                next if user.nil?

                if user.auth_source_id != self.id
                  if user.auth_source_id.blank?
                    puts "-- Skipping user '#{user.login}': intern"
                  else
                    puts "-- Skipping user '#{user.login}': it already exists on a different LDAP server, id:#{user.auth_source_id}"
                  end

                  next
                end

                if !user.valid?
                  puts "-- Could not create user '#{user.login}': \"#{user.errors.full_messages.join('", "')}\""
                  next
                end

                puts "\n-- Creating user #{user.firstname} #{user.lastname}(#{user.login})..." if user_is_fresh
                puts "\n-- Updating user #{user.firstname} #{user.lastname}(#{user.login})..." if !user_is_fresh

                groups = sync_groups_con(user, ldap)
                if groups[:added].present? || groups[:deleted].present?
                  a = groups[:added].size
                  d = groups[:deleted].size
                  print "   -> "
                  print "#{pluralize(a, 'group')} added #{groups[:added].inspect}" if a > 0
                  print " and " if a > 0 && d > 0
                  print "#{pluralize(d, a == 0 ? 'group' : nil)} deleted (#{groups[:deleted].inspect})" if d > 0
                  puts
                end

                # Update user's attribues
                sync_user_attributes_con(user, ldap_con) unless user_is_fresh
              end
            end #ldap_con.open

            if groupname.present?
              if user.groups.exists?(:lastname => groupname)
                if user.locked?
                  user.activate!
                  puts "   -> activated: the user is member of group '#{groupname}'"
                end
              elsif user.active?
                user.lock!
                puts "   -> locked: the user is not member of group '#{groupname}'"
              end
            end
          end

          def sync_user_attributes(user)
            return unless sync_user_attributes?

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            sync_user_attributes_con(user, ldap_con)
          end

          def sync_user_attributes_con(user, ldap_con)
            return unless sync_user_attributes?

            attrs = get_user_dn_con(user.login, ldap_con)
            user.update_attributes(attrs.slice(*settings[:attributes_to_sync].map(&:intern)))
          end

          def lock_unless_member_of(user)
            groupname = settings && settings[:must_be_member_of]
            if groupname.present? && !user.groups.exists?(:lastname => groupname)
              logger.debug "==>locked, NOT member of #{groupname} for #{user.login}" if logger && logger.debug?
              user.lock! 
            end
          end

          def add_to_group
            settings[:add_to_group]
          end

          # Get the user's dn and any attributes for them, given their login
          def get_user_dn_con(login, ldap_con)
            login_filter = Net::LDAP::Filter.eq( self.attr_login, login ) 
            object_filter = Net::LDAP::Filter.eq( "objectClass", "*" ) 
            attrs = {}

            ldap_con.search( :base => self.base_dn, 
                             :filter => object_filter & login_filter, 
                             :attributes=> search_attributes) do |entry|

              if onthefly_register?
                attrs = get_user_attributes_from_ldap_entry(entry)
              else
                attrs = {:dn => entry.dn}
              end

              logger.debug "DN found for #{login}: #{attrs[:dn]}" if logger && logger.debug?
            end

            attrs
          end

          protected

          def ldap_users
            new_ldap_con = initialize_ldap_con(self.account, self.account_password)
            ldap_users_con(new_ldap_con)
          end

          def ldap_users_con(ldap_con)
            return @ldap_users if @ldap_users

            user_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_user] )
            attr_enabled = 'userAccountControl'
            users = {:enabled => [], :disabled => []}

            ldap_con.search(:base => self.base_dn,
                            :filter => user_filter,
                            :attributes => [self.attr_login, attr_enabled],
                            :return_result => false) do |entry|
              if entry[attr_enabled] && entry[attr_enabled][0].to_i & 2 != 0
                users[:disabled] << entry[self.attr_login][0]
              else
                users[:enabled] << entry[self.attr_login][0]
              end
            end

            users[:disabled] += self.users.active.collect(&:login) - users.values.flatten

            @ldap_users = users
          end

          def groups_changes(user)
            return unless ldapsync_active?

            ldap_con = initialize_ldap_con(self.account, self.account_password)
            ldap_con.open do |new_ldap|
              groups_changes_con(user, new_ldap)
            end
          end

          def groups_changes_con(user, ldap)
            return unless ldapsync_active?

            changes = { :added => [], :deleted => [] }

            groupname_pattern   = /#{settings[:groupname_pattern]}/
            attr_groupname      = settings[:attr_groupname]

            # Find which of the user's current groups exist in ldap
            user_groups   = user.groups.select {|g| groupname_pattern =~ g.to_s}
            names_filter  = user_groups.map {|g| Net::LDAP::Filter.eq( attr_groupname, g.to_s )}.reduce(:|)

            find_all_groups(ldap, names_filter, [ attr_groupname ]) do |entry|
              changes[:deleted] << entry[attr_groupname][0]
            end if names_filter

            case settings[:group_membership]
            when 'on_groups'
              attr_member         = settings[:attr_member]
              attr_user_memberid  = settings[:attr_user_memberid]

              # Find user's memberid
              user_dn = user.login

              find_user(ldap, user.login, [attr_user_memberid]) do |entry|
                user_dn = entry[attr_user_memberid][0]
              end unless attr_user_memberid == self.attr_login

              # Find the static groups which the user belongs to
              member_filter = Net::LDAP::Filter.eq( attr_member, user_dn )

              if user_dn
                group_present = false
                find_all_groups(ldap, member_filter, [attr_groupname]) do |entry|
                  if !group_present
                    puts "\n   static groups :"
                    group_present = true
                  end

                  group = entry[attr_groupname][0]
                  if groupname_pattern =~ group
                    puts "      - #{group}"
                    changes[:added] << group
                  else
                    puts "      - #{group} NOT #{groupname_pattern} ~= #{group}"
                  end
                end

                get_dynamic_members_groups(ldap)
                dynamic_member_groups = @dynamic_members_groups[user_dn]
                group_present = false
                if dynamic_member_groups.any?
                  if !group_present
                    puts "\n   dynamic groups :"
                    group_present = true
                  end

                  dynamic_member_groups.each do |dynamic_group|
                    if groupname_pattern =~ dynamic_group
                      puts "      - #{dynamic_group}"
                      changes[:added] << dynamic_group
                    else
                      puts "      - #{gdynamic_group} dynamic NOT #{groupname_pattern} ~= #{dynamic_group}"
                    end
                  end
                end
              end
            else # 'on_members'
              groups_base_dn    = settings[:groups_base_dn]
              attr_user_groups  = settings[:attr_user_groups]
              attr_groupid      = settings[:attr_groupid]

              groups  = []
              find_user(ldap, user.login, [attr_user_groups]) do |entry|
                groups = entry[attr_user_groups].select {|g| g.end_with?(groups_base_dn)}
              end

              names_filter = groups.map{|g| Net::LDAP::Filter.eq( attr_groupid, g )}.reduce(:|)
              find_all_groups(ldap, names_filter, [attr_groupname]) do |entry|
                group = entry[attr_groupname][0]
                changes[:added] << group if groupname_pattern =~ group
              end if names_filter
            end

            changes[:deleted] -= changes[:added]
            changes[:added]   -= user.groups.collect(&:lastname)

            changes
          end

          def find_all_groups(ldap, extra_filter, attrs, &block)
            group_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_group] )
            group_filter &= Net::LDAP::Filter.construct( settings[:group_search_filter] ) if settings[:group_search_filter].present?
            groups_base_dn = settings[:groups_base_dn]

#            puts "      | base=#{groups_base_dn}\n      | group filter=#{group_filter.inspect}]\n      | extra filter=#{extra_filter.inspect}]"
            ldap.search(:base => groups_base_dn,
                        :filter => group_filter & extra_filter,
                        :attributes => attrs,
                        :return_result => false) do |entry|
              yield entry
            end
          end

          def find_all_dynamic_groups(ldap, extra_filter, attrs, &block)
            group_filter = Net::LDAP::Filter.construct( settings[:group_search_filter] ) if settings[:group_search_filter].present?
            groups_base_dn = settings[:groups_base_dn]

#            puts "      | base=#{groups_base_dn}\n      | group filter=#{group_filter.inspect}]\n      | extra filter=#{extra_filter.inspect}]"
            ldap.search(:base => groups_base_dn,
                        :filter => group_filter & extra_filter,
                        :attributes => attrs,
                        :return_result => false) do |entry|
              yield entry
            end
          end

          def get_dynamic_members_groups(ldap)
            _now = Time.now
            if @dynamic_members_groups
              _age = (_now - @dynamic_members_groups_parsed_at).to_i #seconds
            else
              _age = 0
            end

            if @dynamic_members_groups && (_age <= cache_duration)
#              puts "      still in cache [#{@dynamic_members_groups.size}] group(s) (#{_age} <= #{cache_duration} sec.)"
              return @dynamic_members_groups
            end

            @dynamic_members_groups_parsed_at = _now
            @dynamic_members_groups = {}
            dynamic_groups_members = {}

            attr_groupname      = settings[:attr_groupname]
            dynamic_groupes_filter  = Net::LDAP::Filter.eq( 'ObjectClasses', 'groupOfURLs' )
            find_all_dynamic_groups(ldap, dynamic_groupes_filter, [ attr_groupname, 'member' ]) do |entry|
              if entry[:cn].any?
                dynamic_groups_members[entry[:cn].first] = entry[:member]
              end
            end if dynamic_groupes_filter

            dynamic_groups_members.sort_by{ |name, members| name }.each do |dynamic_group_name, dynamic_group_members|
              dynamic_group_members.each do |member|
                if @dynamic_members_groups[member].nil?
                  @dynamic_members_groups[member]=[]
                end
                @dynamic_members_groups[member] << dynamic_group_name
              end
            end

#            @dynamic_members_groups.sort_by{ |name, groups| name }.each do |member_name, dynamic_groups_names|
#              puts "      #{member_name} [#{dynamic_groups_names.size}] groupe(s)"
#            end
            puts "      [#{@dynamic_members_groups.size}] member(s) of dynamic groups"
          end

          def find_user(ldap, login, attrs, &block)
            user_filter = Net::LDAP::Filter.eq( 'objectClass', settings[:class_user] )
            login_filter = Net::LDAP::Filter.eq( self.attr_login, login )
            ldap.search(:base => self.base_dn,
                        :filter => user_filter & login_filter,
                        :attributes => attrs,
                        :return_result => false) do |entry|
              yield entry
            end
          end

          def ldapsync_active?
            settings && settings[:active]
          end

          def sync_user_attributes?
            ldapsync_active? && settings[:sync_user_attributes]
          end

          def create_groups?
            settings && settings[:create_groups]
          end

          def create_users?
            settings && settings[:create_users]
          end

          def pluralize(n, word)
            return word.present? ? "#{n} #{word}#{'s' if n != 1}" : n.to_s
          end

          def settings
            return @settings if @settings

            @settings = Setting.plugin_redmine_ldap_sync[self.name]
          end
        end
      end
    end
  end
end
