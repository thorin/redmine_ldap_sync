# encoding: utf-8
# Copyright (C) 2011-2013  The Redmine LDAP Sync Authors
#
# This file is part of Redmine LDAP Sync.
#
# Redmine LDAP Sync is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Redmine LDAP Sync is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Redmine LDAP Sync.  If not, see <http://www.gnu.org/licenses/>.
module LdapSync
  module VERSION #:nodoc:
    MAJOR = 2
    MINOR = 0
    TINY  = 1

    # Branch values:
    # * official release: nil
    # * stable branch:    stable
    # * trunk:            devel
    BRANCH = nil

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
