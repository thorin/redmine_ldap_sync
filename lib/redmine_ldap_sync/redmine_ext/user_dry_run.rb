module RedmineLdapSync
  module RedmineExt
    module UserDryRun

      module ClassMethods
        def create(attributes)
          user = User.new(attributes)
          yield user if block_given?
          user
        end
      end

      module InstanceMethods
        def lock!();end

        def activate!(); end

        def update_attributes(attrs = {}); end

        def save(*args); end
      end

      def self.included(receiver)
        receiver.extend(ClassMethods)
        receiver.send(:include, InstanceMethods)

        receiver.instance_eval do
          has_and_belongs_to_many :groups do
            def <<(groups)
              puts "   !! Added to groups '#{groups.map(&:lastname).join("', '")}'" unless groups.empty?
            end

            def delete(*groups)
              puts "   !! Removed from groups '#{groups.map(&:lastname).join("', '")}'" unless groups.empty?
            end
          end

          remove_method :lock!, :activate!
        end

      end

    end
  end
end
