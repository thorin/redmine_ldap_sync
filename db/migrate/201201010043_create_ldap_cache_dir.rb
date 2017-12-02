class CreateLdapCacheDir < ActiveRecord::Migration[4.2]

  def self.up
    cache_dir = Rails.root.join("tmp/ldap_cache")
    say_with_time "Creating path '#{cache_dir}'" do
      FileUtils.mkdir_p cache_dir
    end
  end

  def self.down
  end
end
