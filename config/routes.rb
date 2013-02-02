resources :ldap_settings, :path => 'admin/ldap_sync', :only => [:show, :edit, :update, :index]  do
  member do
    put 'test'
    put 'disable'
    put 'enable'
  end
  get 'base_settings', :constraints => { :format => /js/ }, :on => :collection
end
