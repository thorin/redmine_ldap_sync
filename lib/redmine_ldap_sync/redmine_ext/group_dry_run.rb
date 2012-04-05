module RedmineLdapSync
  module RedmineExt
    module GroupDryRun

      def self.included(base)
        base.instance_eval do

          def find_or_create_by_lastname(lastname, attributes)
            group = find_by_lastname(lastname)
            return group if group.present?

            group = Group.new(attributes.merge(:lastname => lastname))
            puts "   !! New group '#{lastname}'" if (group.valid?)

            group
          end

        end
      end

    end
  end
end
