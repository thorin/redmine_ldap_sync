module RedmineLdapSync
  module CoreExt
    module FileStorePatch
      def self.included(base)
        base.class_eval do
          def delete_unless
            options = merged_options(options)
            search_dir(cache_path) do |path|
              key = file_path_key(path)
              delete_entry(key, options) unless yield(key)
            end
          end
        end
      end
    end
  end
end
