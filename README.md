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

+ **Base settings** - Preloads the configuration with predefined settings.
+ **Group base DN** - The path to where the groups are located. Eg,
  `ou=people,dc=smokeyjoe,dc=com`.
+ **Groups objectclass** - The groups object class.
+ **Users objectclass** - The users object class.
+ **Group name pattern** - (optional) An RegExp that should match up with the
  name of the groups that should be imported. Eg, `\.team$`.
+ **Group search filter** - (optional) An LDAP search filter to be applied
  whenever search for groups.
+ **Account disabled test** - A ruby boolean expression that should evaluate an
  account's flags (the variable `flags`) and return `true` if the account is
  disabled. Eg., `flags.to**i & 2 != 0` or `flags.include? 'D'`.
+ **Group membership** - Specifies how to determine the user's group membership.
  The possible values are:
  - **On the group class**: membership determined from the list of users
    contained on the group.
  - **On the user class**: membership determined from the list of groups
    contained on the user.
+ **Enable nested groups** - Enables and specifies how to identify the groups
  nesting. When enabled the plugin will look for the groups' parent groups, and
  so on, and add those groups to the users. The possible values are:
  - **Membership on the parent class** - group membership determined from the
    list of groups contained on the parent group.
  - **Membership on the member class** - group membership determined from the
    list of groups contained on the member group.

**LDAP attributes:**
+ **Group name (group)** - The ldap attribute from where to fetch the
  group's name. Eg, `sAMAccountName`.
+ **Account flags (user)** - The ldap attribute containing the account disabled
  flag. Eg., `userAccountControl`.
+ **Members (group)** - The ldap attribute from where to fetch the
  group's members. Visible if the group membership is __on the group class__.
  Eg, `member`.
+ **Memberid (user)** - The ldap attribute from where to fetch the
  user's memberid. This attribute must match with the __members attribute__.
  Visible if the group membership is __on the group class__. Eg, `dn`.
+ **Groups (user)** - The ldap attribute from where to fetch the user's
  groups. Visible if the group membership is __on the user class__. Eg,
  `memberof`.
+ **Groupid (group)** - The ldap attribute from where to fetch the
  group's groupid. This attribute must match with the __groups attribute__.
  Visible if the group membership is __on the user class__. Eg,
  `distinguishedName`.
+ **Member groups (group)** - The ldap attribute from where to fetch the
  group's member groups. Visible if the nested groups __membership is on the
  parent class__. Eg, `member`.
+ **Memberid attribute (group)** - The ldap attribute from where to fetch the
  member group's memberid. This attribute must match with the __member groups
  attribute__. Eg, `distinguishedName`.
+ **Parent groups (group)** - The ldap attribute from where to fetch
  the group's parent groups. Visible if the nested groups __membership is on
  the member class__. Eg, `memberOf`.
+ **Parentid attribute (group)** - The ldap attribute from where to fetch the
  parent group's id. This attribute must match with the __parent groups
  attribute__. Eg, `distinguishedName`.

**Synchronization actions:**

+ **Users must be members of** - (optional) A group to wich the users must
  belong to to have access enabled to redmine.
+ **Administrators group** - (optional) All members of this group will become
  redmine administrators.
+ **Add users to group** - (optional) A group to wich all the users created
  from this LDAP authentication will added upon creation. This group should not
  exist on LDAP.
+ **Create new groups** - If enabled, groups that don't already exist on
  redmine will be created.
+ **Create new users** - If enabled, users that don't already exist on redmine
  will be created when running the rake task.
+ **User/Group fields:**
  - **Synchronize** - If enabled, the selected attribute will be synchronized
    both on the rake tasks and after every login.
  - **LDAP attribute** - The ldap attribute to be used as reference on the
    synchronization.
  - **Default value** - Shows the value that will be used as default.

### Rake tasks

The following tasks are available:

    # rake -T redmine:plugins:ldap_sync
    rake redmine:plugins:ldap_sync:sync_all     # Synchronize both redmine's users and groups with LDAP
    rake redmine:plugins:ldap_sync:sync_groups  # Synchronize redmine's groups fields with those on LDAP
    rake redmine:plugins:ldap_sync:sync_users   # Synchronize redmine's users fields and groups with those on LDAP

This tasks can be used to do periodic synchronization.
For example:

    # Synchronize users with ldap @ every 60 minutes
    35 *            * * *   root /usr/bin/rake -f /opt/redmine/Rakefile --silent redmine:plugins:ldap_sync:sync_users RAILS_ENV=production 2>&- 1>&-

The tasks recognize two environment variables:
+ **DRY_RUN** - Performs a run without changing the database.
+ **ACTIVATE_USERS** - Activates users if they're active on LDAP.

### Base settings

The base settings read from the plain YAML file `config/base_settings.yml`.
Please be aware that those settings weren't tested and may not work.
Saying so, I'll need your help to make these settings more accurate.

License
-------
This plugin is released under the GPL v3 license. See LICENSE for more
 information.

[uacf]: http://support.microsoft.com/kb/305144
