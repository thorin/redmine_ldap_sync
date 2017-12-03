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
class LdapSettingsController < ApplicationController
  layout 'admin'
  menu_item :ldap_sync

  before_action :require_admin
  before_action :find_ldap_setting, :only => [:show, :edit, :update, :test, :enable, :disable]
  before_action :update_ldap_setting_from_params, :only => [:edit, :update, :test]

  if respond_to? :skip_before_action
    skip_before_action :verify_authenticity_token, :if => :js_request?
  end

  # GET /ldap_settings
  def index
    @ldap_settings = LdapSetting.all

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

  # GET /ldap_settings/1
  def show
    redirect_to edit_ldap_setting_path(@ldap_setting)
  end

  # GET /ldap_settings/1/edit
  def edit
    respond_to do |format|
      format.html # edit.html.erb
    end
  end

  # PUT /ldap_settings/1/disable
  def disable
    @ldap_setting.disable!

    flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path
  end

  # PUT /ldap_settings/1/enable
  def enable
    @ldap_setting.active = true

    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { flash[:error] = l(:error_cannot_enable_with_invalid_settings); redirect_to_referer_or ldap_settings_path }
      end
    end
  end

  # GET /ldap_settings/1/test
  def test
    return render 'ldap_setting_invalid' unless @ldap_setting.valid?

    ldap_test = params[:ldap_test]
    users     = ldap_test.fetch(:test_users, '').split(',')
    groups    = ldap_test.fetch(:test_groups, '').split(',')
    [users, groups].each {|l| l.map(&:strip).reject(&:blank?) }


    @test = LdapTest.new(@ldap_setting)
    @test.bind_user = ldap_test[:bind_user]
    @test.bind_password = ldap_test[:bind_password]

    if @test.valid?
      @test.run_with_users_and_groups(users, groups)
    else
      render 'ldap_test_invalid'
    end
  end

  # PUT /ldap_settings/1
  def update
    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { render 'edit' }
      end
    end
  end

  private

    def js_request?
      request.format.js?
    end

    def update_ldap_setting_from_params
      %w(user group).each do |e|
        params[:ldap_setting]["#{e}_fields_to_sync"] = params["#{e}_fields_to_sync"]
        params[:ldap_setting]["#{e}_ldap_attrs"] = params["#{e}_ldap_attrs"]
      end if params[:ldap_setting]
      @ldap_setting.safe_attributes = params[:ldap_setting] if params[:ldap_setting]
    end

    def find_ldap_setting
      @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(params[:id])
      render_404 if @ldap_setting.nil?
    end
end
