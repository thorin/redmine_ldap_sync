class RedmineLdapSyncRedmineHooks < Redmine::Hook::Listener
  def controller_account_success_authentication_after(context)
    user = context[:user]

    if user.auth_source && user.auth_source.auth_method_name == 'LDAP'
      user.auth_source.sync_groups(user)
    end
  end
end
