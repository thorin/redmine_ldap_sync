Redmine Ldap Sync
=================

This plugins extends redmine's ldap authentication to perform group synchronization.
In addition it provides a rake task to perform full user group synchronization.

The following should be noted:

* The plugin has only been tested with Active Directory.
* It detects and disables users that have been marked as disabled on LDAP (see [MS KB Article 305144][uacf] for more details).
* An user will only be removed from groups that exist on LDAP. This means that both ldap and non-ldap groups can coexist.
* Deleted groups on LDAP will not be deleted on redmine.

Installation
------------

Follow the plugin installation procedure described at www.redmine.org/wiki/redmine/Plugins

Usage
-----

### Configuration

Open Administration > Plugins and on the plugin configuration page you'll be able to set for each LDAP authentication:

* *Active* - Enable/Disable user/group synchronization for this LDAP authentication
* *Group base DN* - The path to where the groups located. Eg, `ou=people,dc=smokeyjoe,dc=com`
* *Group name* - The ldap attribute from where to fetch the group's name. Eg, `sAMAccountName`
* *Group regex filter* - (optional) An RegExp that should match up with the name of the groups that should be imported. Eg, `\.team$`.
* *Domain group* - (optional) A group to wich all the users created from this LDAP authentication will added upon creation. The group should not exist on LDAP.

### Full user/group synchronization with rake

To do the full user synchronization execute the following:

    rake redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production


An alternative is to do it periodically with a cron task:

    # Synchronize users with ldap @ every 60 minutes
    35 *            * * *   root /usr/bin/rake -f /opt/redmine/Rakefile --silent redmine:plugins:redmine_ldap_sync:sync_users RAILS_ENV=production

License
-------
This plugin is released under the GPL v3 license. See LICENSE for more information.

[uacf]: http://support.microsoft.com/kb/305144
