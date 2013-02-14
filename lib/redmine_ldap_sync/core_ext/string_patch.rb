module RedmineLdapSync::CoreExt::StringPatch
  def raw_utf8_encoded
    if self.respond_to?(:encode)
      # Strings should be UTF-8 encoded according to LDAP.
      # However, the BER code is not necessarily valid UTF-8
      # self.encode('UTF-8', invalid: :replace, undef: :replace, replace: '' ).force_encoding('ASCII-8BIT')
      begin
        self.encode('UTF-8').force_encoding('ASCII-8BIT')
      rescue Encoding::UndefinedConversionError
        self
      end
    else
      self
    end
  end
  private :raw_utf8_encoded
end
