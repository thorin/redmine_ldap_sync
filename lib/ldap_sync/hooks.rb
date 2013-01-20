module LdapSync
  class Hooks < Redmine::Hook::ViewListener

    # Add a question CSS class
    def view_layouts_base_html_head(context = { })
    	stylesheet_link_tag 'ldap_sync.css', :plugin => 'redmine_ldap_sync'
    end

  end
end