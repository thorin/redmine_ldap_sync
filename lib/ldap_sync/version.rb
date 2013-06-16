module LdapSync
  module VERSION #:nodoc:
    MAJOR = 2
    MINOR = 0
    TINY  = 1

    # Branch values:
    # * official release: nil
    # * stable branch:    stable
    # * trunk:            devel
    BRANCH = 'devel'

    # Retrieves the revision from the working copy
    def self.revision
      cwd = File.dirname(__FILE__)
      if File.directory?(File.join(cwd, '..', '..', '.git'))
        begin
          git_description = Dir.chdir(cwd) { `git describe --long --dirty --abbrev=10 --tags` }
          if git_description =~ /.*?-\d+-([0-9a-z-]+)/
            return $1
          end
        rescue
          # Could not find the current revision
        end
      end
      nil
    end

    REVISION = self.revision
    ARRAY    = [MAJOR, MINOR, TINY, BRANCH, REVISION].compact
    STRING   = ARRAY.join('.')

    def self.to_a; ARRAY  end
    def self.to_s; STRING end
  end
end