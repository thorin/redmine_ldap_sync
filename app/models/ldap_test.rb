class LdapTest
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :ldap_setting, :result, :users

  def initialize(ldap_setting)
    @ldap_setting = ldap_setting
  end
end
