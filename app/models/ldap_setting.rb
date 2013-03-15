class LdapSetting
  include Redmine::SafeAttributes
  include Redmine::I18n

  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModel::Conversion
  extend ActiveModel::Naming
  include ActiveModel::AttributeMethods

  # LDAP_DESCRIPTORS
  LDAP_ATTRIBUTES = %w( groupname member user_memberid user_groups groupid parent_group group_parentid member_group group_memberid account_flags )
  CLASS_NAMES = %w( class_user class_group )
  FLAGS = %w( create_groups create_users active )
  COMBOS = %w( group_membership nested_groups sync_on_login dyngroups )
  OTHERS = %w( account_disabled_test user_fields_to_sync group_fields_to_sync user_ldap_attrs group_ldap_attrs fixed_group admin_group required_group group_search_filter groupname_pattern groups_base_dn dyngroups_cache_ttl )

  validates_presence_of :auth_source_ldap_id
  validates_presence_of :groups_base_dn, :class_user, :class_group, :groupname
  validates_presence_of :member, :user_memberid, :if => :membership_on_groups?
  validates_presence_of :user_groups, :groupid, :if => :membership_on_members?
  validates_presence_of :parent_group, :group_parentid, :if => :nested_on_members?
  validates_presence_of :member_group, :group_memberid, :if => :nested_on_parents?
  validates_presence_of :dyngroups_cache_ttl, :if => :dyngroups_enabled_with_ttl?

  validates_inclusion_of :nested_groups, :in => ['on_members', 'on_parents', '']
  validates_inclusion_of :group_membership, :in => ['on_groups', 'on_members']
  validates_inclusion_of :sync_on_login, :in => ['user_fields', 'user_fields_and_groups', '']
  validates_inclusion_of :dyngroups, :in => ['enabled', 'enabled_with_ttl', '']

  validates_format_of *(LDAP_ATTRIBUTES + [{ :with => /\A[a-z][a-z0-9-]*\z/i, :allow_blank => true }])

  validates_numericality_of :dyngroups_cache_ttl, :only_integer => true, :allow_blank => true

  validate :validate_groupname_pattern
  validate :validate_account_disabled_test
  validate :validate_group_filter
  validate :validate_user_fields_to_sync, :validate_user_ldap_attrs
  validate :validate_group_fields_to_sync, :validate_group_ldap_attrs

  before_validation :strip_names, :set_ldap_attrs, :set_fields_to_sync

  delegate :base_dn, :account, :account_password, :filter, :ldap_filter, :to => :auth_source_ldap

  attribute_method_affix :prefix => 'has_', :suffix => '?'
  attribute_method_suffix '?', '='

  safe_attributes *(LDAP_ATTRIBUTES + CLASS_NAMES + FLAGS + COMBOS + OTHERS)
  define_attribute_methods LDAP_ATTRIBUTES + CLASS_NAMES + FLAGS + COMBOS + OTHERS

  [:login, *User::STANDARD_FIELDS].each {|f| module_eval("def #{f}; auth_source_ldap.attr_#{f}; end") }

  def id
    @auth_source_ldap_id
  end

  def name
    auth_source_ldap.name
  end

  def active?
    return @active if defined? @active

    @active = active.in?(true, '1', 'yes')
  end

  def active=(value)
    @active = value
    @attributes[:active] = value
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

  def sync_user_fields?
    has_user_fields_to_sync?
  end

  def sync_group_fields?
    has_group_fields_to_sync?
  end

  def sync_dyngroups?
    has_dyngroups?
  end

  def dyngroups_enabled_with_ttl?
    dyngroups == 'enabled_with_ttl'
  end

  def sync_on_login?
    has_sync_on_login?
  end

  def sync_groups_on_login?
    sync_on_login == 'user_fields_and_groups'
  end

  def sync_fields_on_login?
    has_sync_on_login?
  end

  def account_disabled_proc
    @account_disabled_proc ||= if has_account_disabled_test?
      eval("lambda { |flags| #{account_disabled_test} }")
    end
  end

  def groupname_regexp
    @groupname_regexp ||= /#{groupname_pattern}/i
  end

  def user_ldap_attrs_to_sync
    (user_fields_to_sync||[]).map {|f| user_ldap_attrs[f] || send(f) }
  end

  def group_ldap_attrs_to_sync
    (group_fields_to_sync||[]).map {|f| group_ldap_attrs[f] }
  end

  def ldap_attributes(*names)
    names.map {|n| send(n) }
  end

  def group_field(ldap_attr)
    ldap_attr = ldap_attr.to_s
    group_ldap_attrs.find {|(k, v)| v.downcase == ldap_attr }.try(:first)
  end

  def user_field(ldap_attr)
    ldap_attr = ldap_attr.to_s
    result = @user_standard_ldap_attrs.find {|(k, v)| v.downcase == ldap_attr }.try(:first)
    result ||= user_ldap_attrs.find {|(k, v)| v.downcase == ldap_attr }.try(:first)
  end

  def test
    @ldap_test ||= LdapTest.new(self)
  end

  def initialize(source)
    @attributes = HashWithIndifferentAccess.new

    self.auth_source_ldap = source
    @attributes.merge!(settings)
    @user_standard_ldap_attrs = User::STANDARD_FIELDS.each_with_object({}) {|f, h| h[f] = (send(f)||'').downcase }
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

  def disable!
    self.active = false
    self.settings = settings.merge(:active => false)
  end

  def read_attribute_for_validation(key)
    @attributes[key]
  end

  def persisted?
    true
  end

  def self.human_attribute_name(attr, *args)
    attr = attr.to_s.sub(/_id$/, '')

    l("field_#{name.underscore.gsub('/', '_')}_#{attr}", :default => ["field_#{attr}".to_sym, attr])
  end

  def self.find_by_auth_source_ldap_id(id)
    return unless source = AuthSourceLdap.find_by_id(id)

    LdapSetting.new(source)
  end

  def self.all(options = {})
    AuthSourceLdap.all(options).map {|source| find_by_auth_source_ldap_id(source.id) }
  end

  protected

    def validate_account_disabled_test
      if account_disabled_test.present?
        eval("lambda { |flags| #{account_disabled_test} }")
      end
    rescue Exception => e
      # TODO: Add some extra detail to the error (example the log error)
      errors.add :account_disabled_test, :invalid_expression, :error_message => e.message.gsub(/^(\(eval\):1: )?(.*?)(lambda.*|$)/m, '\2')
      Rails.logger.error e.message + "\n " + e.backtrace.join("\n ")
    end

    def validate_groupname_pattern
      /#{groupname_pattern}/ if groupname_pattern.present?
    rescue Exception => e
      errors.add :groupname_pattern, :invalid_regexp, :error_message => e.message #.gsub(/(.*)/, '\1')
    end

    def validate_group_filter
      Net::LDAP::Filter.construct(group_search_filter) if group_search_filter.present?
    rescue Net::LDAP::LdapError
      errors.add :group_search_filter, :invalid
    end

    def validate_user_ldap_attrs
      validate_ldap_attrs user_ldap_attrs, UserCustomField.all
    end

    def validate_user_fields_to_sync
      validate_fields user_fields_to_sync, (User::STANDARD_FIELDS + UserCustomField.all), user_ldap_attrs
    end

    def validate_group_ldap_attrs
      validate_ldap_attrs group_ldap_attrs, GroupCustomField.all
    end

    def validate_group_fields_to_sync
      validate_fields group_fields_to_sync, GroupCustomField.all, group_ldap_attrs
    end

    def validate_ldap_attrs(ldap_attrs, fields)
      if ldap_attrs.nil?
        errors.add :user_group_fields, :invalid; return
      end

      field_ids = fields.map {|f| f.id.to_s }
      ldap_attrs.each do |k, v|
        if !k.in? field_ids
          errors.add :user_group_fields, :invalid unless errors.added? :user_group_fields, :invalid

        elsif v.present? && v !~ /\A[a-z][a-z0-9-]*\z/i
          field_name = fields.find {|f| f.id == k.to_i }.name
          errors.add :base, :invalid_ldap_attribute, :field => field_name
        end
      end
    end

    def validate_fields(fields_to_sync, fields, attrs)
      if fields_to_sync.nil?
        errors.add :user_group_fields, :invalid; return
      end

      fields_ids = fields.map {|f| f.is_a?(String) ? f : f.id.to_s }
      if fields_to_sync.any? {|f| !f.in? fields_ids  }
        errors.add :user_group_fields, :invalid unless errors.added? :user_group_fields, :invalid
      end
      fields_to_sync.each do |f|
        if f =~ /\A\d+\z/ && (attrs.blank? || attrs[f].blank?)
          field_name = fields.find{|c| !c.is_a?(String) && c.id.to_s == f }.name
          errors.add :base, :must_have_ldap_attribute, :field => field_name
        end
      end
    end

  private

    def set_fields_to_sync
      self.user_fields_to_sync ||= []
      self.group_fields_to_sync ||= []
    end

    def set_ldap_attrs
      self.user_ldap_attrs ||= {}
      self.group_ldap_attrs ||= {}
    end

    def strip_names
      LDAP_ATTRIBUTES.each {|a| @attributes[a].strip! unless @attributes[a].nil? }
      CLASS_NAMES.each {|a| @attributes[a].strip! unless @attributes[a].nil? }
    end

    def attributes
      @attributes
    end

    def attribute(attr)
      @attributes[attr]
    end

    def attribute=(attr, value)
      @attributes[attr] = value
    end

    def attribute?(attr)
      @attributes[attr].in? true, '1', 'yes'
    end

    def has_attribute?(attr)
      self.send("#{attr}").present?
    end

    def self.settings(source)
      Setting.plugin_redmine_ldap_sync.fetch(source.id, HashWithIndifferentAccess.new)
    end

    def settings
      LdapSetting.settings(@auth_source_ldap)
    end

    def settings=(attrs)
      Setting.plugin_redmine_ldap_sync = Setting.plugin_redmine_ldap_sync.merge!(@auth_source_ldap.id => attrs)
    end
end