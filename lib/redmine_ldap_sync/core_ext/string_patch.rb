module RedmineLdapSync::CoreExt::StringPatch
  def raw_utf8_encoded
    if self.respond_to?(:encode) && self.encoding.name != 'ASCII-8BIT'
      # Strings should be UTF-8 encoded according to LDAP.
      # However, the BER code is not necessarily valid UTF-8
      if self.encoding.name != 'UTF-8'
        self.encode('UTF-8').force_encoding('ASCII-8BIT')
      else
        self.force_encoding('ASCII-8BIT')
      end
    else
      self
    end
  end
  private :raw_utf8_encoded
end
