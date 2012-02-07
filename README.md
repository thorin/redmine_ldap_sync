Redmine Ldap Sync
=================

This plugins extends redmine's ldap authentication to perform group
synchronization.
In addition it provides a rake task to perform full user group synchronization.

__Features__:

 * Detects and disables users that have been removed from LDAP.
 * Detects and disables users that have been marked as disabled on Active
 Directory (see [MS KB Article 305144][uacf] for more details).
 * Can detect and include nested groups. Upon login the nested groups are 
 retrieve from disk cache. This cache will only be updated by running the rake
 task.

__Remarks__:

* The plugin has only been tested with Active Directory and OpenLDAP but should
work with other directories.
* An user will only be removed from groups that exist on LDAP. This means that
 both ldap and non-ldap groups can coexist.
* Deleted groups on LDAP will not be deleted on redmine.

Installation & Upgrade
----------------------

For both upgrade and installation please follow the plugin installation 
procedure described at http://www.redmine.org/wiki/redmine/Plugins

Usage
-----

### Configuration

Open Administration > Plugins and on the plugin configuration page you'll be
able to set for each LDAP authentication.

**LDAP settings:**

+ _Active_ - Enable/Disable user/group synchronization for this LDAP
  authentication.
+ _Group base DN_ - The path to where the groups located. Eg,
  `ou=people,dc=smokeyjoe,dc=com`.
+ _Group name attribute (group)_ - The ldap attribute from where to fetch the
  group's name. Eg, `sAMAccountName`.
+ _Group membership_ - Specifies how to determine the user's group membership.
  The possible values are:
  - **On the group class**: membership determined from the list of users
    contained on the group.
  - **On the user class**: membership determined from the list of groups
    contained on the user.
+ _Members attribute (group)_ - The ldap attribute from where to fetch the
  group's members. Visible if the group membership is __on the group class__.
  Eg, `member`.
+ _Memberid attribute (user)_ - The ldap attribute from where to fetch the
  user's memberid. This attribute must match with the __members attribute__.
  Visible if the group membership is __on the group class__. Eg, `dn`.
+ _Groups attribute (user)_ - The ldap attribute from where to fetch the user's
  groups. Visible if the group membership is __on the user class__. Eg,
  `memberof`.
+ _Groupid attribute (group)_ - The ldap attribute from where to fetch the
  group's groupid. This attribute must match with the __groups attribute__.
  Visible if the group membership is __on the user class__. Eg,
  `distinguishedName`.
+ _Groups objectclass_ - The groups object class.
+ _Users objectclass_ - The users object class.
+ _Group name pattern_ - (optional) An RegExp that should match up with the name
  of the groups that should be imported. Eg, `\.team$`.
+ _Group search filter_ - (optional) An LDAP search filter to be applied
  whenever search for groups.
+ _Enable nested groups_ - Enables and specifies how to identify the groups 
nesting. When enabled the plugin will look for the groups' parent groups, and
so on, and add those groups to the users.
  - **Membership on the parent class** - group membership determined from the 
    list of groups contained on the parent group.
  - **Membership on the member class** - group membership determined from the 
    list of groups contained on the member group.
+ _Member groups attribute (group)_ - The ldap attribute from where to fetch the
group's member groups. Visible if the nested groups __membership is on the 
parent class__. Eg, `member`.
+ _Parent groups attribute (group)_ - The ldap attribute from where to fetch the
group's parent groups. Visible if the nested groups __membership is on the 
member class__. Eg, `memberOf`.
+ _Memberid attribute (group)_ - The ldap attribute from where to fetch the 
member group's memberid. This attribute must match with the __member groups 
attribute__. Eg, `distinguishedName`.
+ _Parentid attribute (group)_ - The ldap attribute from where to fetch the 
parent group's id. This attribute must match with the __parent groups 
attribute__. Eg, `distinguishedName`.

**Synchronization Actions:**

+ _Users must be members of_ - (optional) A group to wich the users must belong
  to to have access enabled to redmine.
+ _Add users to group_ - (optional) A group to wich all the users created from
  this LDAP authentication will added upon creation. The group should not exist
 on LDAP.
+ _Create new groups_ - If enabled, groups that don't already exist on redmine
  will be created.
+ _Create new users_ - If enabled, users that don't already exist on redmine
  will be created when running the rake task.
+ _Sync users attributes_ - If enabled, the selected attributes will
  synchronized both on the rake tasks and after every login.
+ _Attributes to be synced_ - The attributes to be synchronized: "First name",
  "Last name" and/or "Email"

### Full user/group synchronization with rake

To do the full user synchronization execute the following:

    rake redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production


An alternative is to do it periodically with a cron task:

    # Synchronize users with ldap @ every 60 minutes
    35 *            * * *   root /usr/bin/rake -f /opt/redmine/Rakefile --silent redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production 2>&- 1>&-

LDAP Compatibility
------------------
### Active Directory
+ _Group membership_ = on the group class | {on the user class}
+ _Group name attribute (group)_ = sAMAccountName
+ _Members attribute (group)_ = member
+ _Memberid attribute (user)_ = dn
+ _Groups attribute (user)_ = ---   | {memberof}
+ _Groupid attribute (group)_ = --- | {distinguishedName}
+ _Groups objectclass_ = group
+ _Users objectclass_ = user
+ _Nested groups_ = membership on the parent class | {membership on the member class}
+ _Member groups attribute (group)_ - member
+ _Memberid attribute (group)_ - distinguishedName
+ _Parent groups attribute (group)_ - --- | {memberof}
+ _Parentid attribute (group)_ - ---      | {distinguishedName}

### OpenDS
+ _Group name attribute (group)_ = cn
+ _Group membership_ = on the user class
+ _Groups attribute (user)_ = isMemberOf
+ _Memberid attribute (user)_ = entryDN
+ _Groups objectclass_ = groupOfUniqueNames
+ _Users objectclass_ = person

### Lotus Notes LDAP (tested against Lotus Notes 8.5.2)
+ _Group membership_ = on the group class
+ _Group name attribute (group)_ = cn
+ _Members attribute (group)_ = member
+ _Memberid attribute (user)_ = dn
+ _Groups objectclass_ = dominoGroup
+ _Users objectclass_ = dominoPerson

### Open LDAP (with posixGroups)
+ _Group membership_ = on the group class
+ _Group name attribute_ = cn
+ _Members attribute_ = member
+ _Groups objectclass_ = posixGroup
+ _Users objectclass_ = person

License
-------
This plugin is released under the GPL v3 license. See LICENSE for more
 information.

[uacf]: http://support.microsoft.com/kb/305144
