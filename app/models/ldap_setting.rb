class LdapSetting
  include Redmine::SafeAttributes

  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModel::Conversion
  extend ActiveModel::Naming
  include ActiveModel::AttributeMethods

  validates_presence_of :auth_source_ldap_id
  validates_presence_of :groups_base_dn, :class_user, :class_group, :groupname, :if => :active?
  validates_presence_of :member, :user_memberid, :if => :membership_on_groups?
  validates_presence_of :user_groups, :groupid, :if => :membership_on_members?
  validates_presence_of :parent_group, :group_parentid, :if => :nested_on_members?
  validates_presence_of :member_group, :group_memberid, :if => :nested_on_parents?

  validates_inclusion_of :nested_groups, :in => ['on_members', 'on_parents', '']
  validates_inclusion_of :group_membership, :in => ['on_groups', 'on_members']

  validate :validate_group_filter

  before_validation :strip_names

  # after_save :validate_auth_ldap_id (if account.include? "$login" :cannot_sync_users_and_groups )

  ## This will be done on a execution test
  # validates :groups_base_dn ---- find object on ldap
  # validates :class_user ---- find this class on ldap
  # validates :class_group ---- find this class on ldap
  # validates :groupname ---- validate that a group has this attribute
  # validates :member ---- validate that a group has this attribute
  # validates :user_memberid ---- validate that a user has this attribute
  # validates :user_groups ---- validate that a user has this attribute
  # validates :groupid ---- validate that a group has this attribute
  # validates :parent_group ---- valitade that a group has this attribute
  # validates :group_parentid ---- valitade that a group has this attribute
  # validates :member_group ---- valitade that a group has this attribute
  # validates :group_memberid ---- valitade that a group has this attribute

  LDAP_ATTRIBUTES = %w( groupname member user_memberid user_groups groupid parent_group group_parentid member_group group_memberid account_flags )
  CLASS_NAMES = %w( class_user class_group )
  FLAGS = %w( create_groups create_users sync_user_attributes active )
  COMBOS = %w( group_membership nested_groups )
  OTHER = %w( account_disabled_test attributes_to_sync fixed_group required_group group_search_filter groupname_pattern groups_base_dn )

  attribute_method_affix :prefix => 'has_', :suffix => '?'
  attribute_method_suffix '?', '='

  safe_attributes *LDAP_ATTRIBUTES, *CLASS_NAMES, *FLAGS, *COMBOS, *OTHER
  define_attribute_methods [*LDAP_ATTRIBUTES, *CLASS_NAMES, *FLAGS, *COMBOS, *OTHER]

  def validate_group_filter
    Net::LDAP::Filter.construct(group_search_filter) if group_search_filter.present?
  rescue Net::LDAP::LdapError
    errors.add(:group_search_filter, :invalid)
  end

  def id
    @auth_source_ldap_id
  end

  def name
    auth_source_ldap.name
  end

  def active?
    return @active if defined? @active

    @active = [true, '1', 'yes'].include? active
  end

  def sync_user_attributes?
    self.active? && [true, '1', 'yes'].include?(sync_user_attributes)
  end

  def nested_groups_enabled?
    self.active? && nested_groups.present?
  end

  def nested_on_members?
    self.active? && nested_groups == 'on_members'
  end

  def nested_on_parents?
    self.active? && nested_groups == 'on_parents'
  end

  def membership_on_groups?
    self.active? && group_membership == 'on_groups'
  end

  def membership_on_members?
    self.active? && group_membership == 'on_members'
  end

  def test
    @ldap_test ||= LdapTest.new(self)
  end

  def initialize(source)
    @attributes = HashWithIndifferentAccess.new

    self.auth_source_ldap = source
    @attributes.merge!(settings)
  end

  def auth_source_ldap_id=(id)
    @auth_source_ldap_id = id
    source = AuthSourceLdap.find_by_id(id)
    self.auth_source_ldap = source unless source.nil?
  end

  def auth_source_ldap
    @auth_source_ldap
  end

  def auth_source_ldap=(source)
    @auth_source_ldap = source
    @auth_source_ldap_id  = source.id
    @attributes[:auth_source_ldap_id] = source.id
  end

  def safe_attributes=(attrs, user = User.current)
    @attributes.merge!(delete_unsafe_attributes(attrs, user))
  end

  def save
    return false if invalid?

    self.settings = delete_unsafe_attributes(@attributes, User.current)
  end

  def read_attribute_for_validation(key)
    @attributes[key]
  end

  def persisted?
    true
  end

  def to_param
    @to_param ||= @auth_source_ldap_id
  end

  def self.find_by_auth_source_ldap_id(id)
    return unless source = AuthSourceLdap.find_by_id(id)

    LdapSetting.new(source)
  end

  def self.all(options = {})
    AuthSourceLdap.all(options).map {|source| find_by_auth_source_ldap_id(source.id) }
  end

  def self.count(options = {})
    AuthSourceLdap.count(options)
  end

  def self.find(method, options = {})
    AuthSourceLdap.find(method, options).map {|source| find_by_auth_source_ldap_id(source.id) }
  end

  private

    def strip_names
      LDAP_ATTRIBUTES.each { |a| @attributes[a].strip! unless @attributes[a].nil? }
    end

    def attribute(attr)
      @attributes[attr]
    end

    def attribute=(attr, value)
      @attributes[attr] = value
    end

    def attribute?(attr)
      [true, '1', 'yes'].include?(@attributes[attr])
    end

    def has_attribute?(attr)
      self.send("#{attr}").present?
    end

    def self.settings(source)
      Setting.plugin_redmine_ldap_sync.fetch(source.name, HashWithIndifferentAccess.new)
    end

    def settings
      LdapSetting.settings(@auth_source_ldap)
    end

    def settings=(attrs)
      Setting.plugin_redmine_ldap_sync = Setting.plugin_redmine_ldap_sync.merge!(@auth_source_ldap.name => attrs)
    end
end
