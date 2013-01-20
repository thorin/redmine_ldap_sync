module LdapSync::DryRun::Group

  module InstanceMethods
    def find_or_create_by_lastname(lastname, attributes = {})
      group = find_by_lastname(lastname)
      return group if group.present?

      group = ::Group.new(attributes.merge(:lastname => lastname))
      puts "   !! New group '#{lastname}'" if (group.valid?)

      group
    end
  end

  def self.included(receiver)
    receiver.send(:include, InstanceMethods)

    receiver.instance_eval do
      has_and_belongs_to_many :users do
        def <<(users)
          puts "   !! Added to group '#{proxy_association.owner.lastname}'"
        end
      end
    end
  end

end
