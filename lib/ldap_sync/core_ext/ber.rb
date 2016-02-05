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
if ('0.12.0'..'0.13.0') === Gem.loaded_specs['net-ldap'].version.to_s
  require 'net/ber'

  ##
  # A String object with a BER identifier attached.
  #
  class Net::BER::BerIdentifiedString < String
    attr_accessor :ber_identifier

    # The binary data provided when parsing the result of the LDAP search
    # has the encoding 'ASCII-8BIT' (which is basically 'BINARY', or 'unknown').
    #
    # This is the kind of a backtrace showing how the binary `data` comes to
    # BerIdentifiedString.new(data):
    #
    #  @conn.read_ber(syntax)
    #     -> StringIO.new(self).read_ber(syntax), i.e. included from module
    #     -> Net::BER::BERParser.read_ber(syntax)
    #        -> (private)Net::BER::BERParser.parse_ber_object(syntax, id, data)
    #
    # In the `#parse_ber_object` method `data`, according to its OID, is being
    # 'casted' to one of the Net::BER:BerIdentifiedXXX classes.
    #
    # As we are using LDAP v3 we can safely assume that the data is encoded
    # in UTF-8 and therefore the only thing to be done when instantiating is to
    # switch the encoding from 'ASCII-8BIT' to 'UTF-8'.
    #
    # Unfortunately, there are some ActiveDirectory specific attributes
    # (like `objectguid`) that should remain binary (do they really?).
    # Using the `#valid_encoding?` we can trap this cases. Special cases like
    # Japanese, Korean, etc. encodings might also profit from this. However
    # I have no clue how this encodings function.
    def initialize args
      super
      #
      # Check the encoding of the newly created String and set the encoding
      # to 'UTF-8' (NOTE: we do NOT change the bytes, but only set the
      # encoding to 'UTF-8').
      current_encoding = encoding
      if current_encoding == Encoding::BINARY
        force_encoding('UTF-8')
        force_encoding(current_encoding) unless valid_encoding?
      end
    end
  end
end