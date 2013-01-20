require File.expand_path('../../test_helper', __FILE__)

class LdapSettingTest < ActiveModel::TestCase
  include ActiveModel::Lint::Tests

  def setup
  	@auth_source = auth_sources(:auth_sources_001)
    @model = LdapSetting.find_by_auth_source_ldap_id(@auth_source.id)
  end

  # Replace this with your real tests.
  def test_truth
    assert true
  end
end
