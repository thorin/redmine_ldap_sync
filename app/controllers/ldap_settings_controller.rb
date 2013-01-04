class LdapSettingsController < ApplicationController
  layout 'admin'
  menu_item :ldap_sync

  before_filter :require_admin
  before_filter :find_ldap_setting, :only => [:edit, :test, :update, :enable, :disable]

  # GET /ldap_settings
  # GET /ldap_settings.json
  def index
    @ldap_settings_pages, @ldap_settings = paginate LdapSetting, :per_page => 10

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # GET /ldap_settings/base_settings.js
  def base_settings
    respond_to do |format|
      format.js # base_settings.js.erb
    end
  end

  # GET /ldap_settings/1/edit
  def edit
    update_ldap_setting_from_params

    respond_to do |format|
      format.html # edit.html.erb
    end
  end

  # PUT /ldap_settings/1/disable
  def disable
    @ldap_setting.active = false

    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { flash[:error] = @ldap_setting.errors.full_messages.join(', '); redirect_to_referer_or ldap_settings_path }
      end
    end
  end

  # PUT /ldap_settings/1/disable
  def enable
    @ldap_setting.active = true

    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { flash[:error] = @ldap_setting.errors.full_messages.join(', '); redirect_to_referer_or ldap_settings_path }
      end
    end
  end

  # GET /ldap_settings/1/test
  def test
    update_ldap_setting_from_params

  end

  # PUT /ldap_settings/1
  # PUT /ldap_settings/1.json
  def update
    update_ldap_setting_from_params

    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { render action: "edit" }
      end
    end
  end

  private

  def update_ldap_setting_from_params
    @ldap_setting.safe_attributes = params[:ldap_setting] if params[:ldap_setting]
  end

  def find_ldap_setting
    @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
