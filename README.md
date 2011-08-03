Redmine Ldap Sync
=================

This plugins extends redmine's ldap authentication to perform group 
synchronization.
In addition it provides a rake task to perform full user group synchronization.

The following should be noted:

* The plugin has only been tested with Active Directory but should work with
other directories.
* It detects and disables users that have been marked as disabled on LDAP (see
 [MS KB Article 305144][uacf] for more details).
* An user will only be removed from groups that exist on LDAP. This means that
 both ldap and non-ldap groups can coexist.
* Deleted groups on LDAP will not be deleted on redmine.

Installation
------------

Follow the plugin installation procedure described at 
http://www.redmine.org/wiki/redmine/Plugins

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
+ _Group name attribute_ - The ldap attribute from where to fetch the group's
  name. Eg, `sAMAccountName`.
+ _Members attribute_ - The ldap attribute from where to fetch the group's
  members. Eg, `member`.
+ _Groups objectclass_ - The groups object class.
+ _Users objectclass_ - The users object class.
+ _Group name pattern_ - (optional) An RegExp that should match up with the name
  of the groups that should be imported. Eg, `\.team$`.
+ _Group search filter_ - (optional) An LDAP search filter to be applied
  whenever search for groups.

**Synchronization Actions:**

+ _Users must be members of_ - (optional) A group to wich the users must belong
  to to have access enabled to redmine.
+ _Add users to group_ - (optional) A group to wich all the users created from
  this LDAP authentication will added upon creation. The group should not exist
 on LDAP.
+ _Create new groups_ - If enabled, groups that don't already exist on redmine
  will be created.
+ _Sync users attributes_ - If enabled, the selected attributes will
  synchronized both on the rake tasks and after every login.
+ _Attributes to be synced_ - The attributes to be synchronized: "First name",
  "Last name" and/or "Email"

### Full user/group synchronization with rake

To do the full user synchronization execute the following:

    rake redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production


An alternative is to do it periodically with a cron task:

    # Synchronize users with ldap @ every 60 minutes
    35 *            * * *   root /usr/bin/rake -f /opt/redmine/Rakefile --silent redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production

LDAP Compatibility
------------------
### Active Directory
+ _Group name attribute_ = sAMAccountName
+ _Members attribute_ = member
+ _Groups objectclass_ = group
+ _Users objectclass_ = user

### eDirectory / Open LDAP
+ _Group name attribute_ = cn / ??
+ _Members attribute_ = member
+ _Groups objectclass_ = groupOfNames
+ _Users objectclass_ = person / organizationalPerson

License
-------
This plugin is released under the GPL v3 license. See LICENSE for more
 information.

[uacf]: http://support.microsoft.com/kb/305144
