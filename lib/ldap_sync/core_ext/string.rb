require 'net/ldap'

module Net::BER::Extensions::String
  def raw_utf8_encoded
    if self.respond_to?(:encode) && self.encoding.name != 'ASCII-8BIT'
      self.encode('UTF-8').force_encoding('ASCII-8BIT')
    else
      self
    end
  end
end