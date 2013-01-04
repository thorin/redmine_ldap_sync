require File.expand_path('../../test_helper', __FILE__)

class LdapSettingTest < ActiveModel::TestCase
  include ActiveModel::Lint::Tests

  def setup
    @model = LdapSetting.new
  end

  # Replace this with your real tests.
  def test_truth
    assert true
  end
end
