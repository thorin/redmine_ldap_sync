module RedmineLdapSync
  module RedmineExt
    module UserDryRun

      def self.included(base)

        base.class_eval do
          def lock!; end

          def activate!; end
        end

        base.instance_eval do
          has_and_belongs_to_many :groups do
            def <<(groups)
              puts "   !! Adding groups '#{groups.map(&:lastname).join("', '")}'" unless groups.empty?
            end
          end

          def create(attributes)
            user = User.new(attributes)
            yield user if block_given?
            user
          end
        end

      end

    end
  end
end
