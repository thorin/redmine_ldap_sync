function show_options(elem, prefix) {
  if ($(elem).val() != '') $('#' + prefix + $(elem).val()).show();
  if (!elem.options) return;
  for (var j = elem.options.length >>> 0; j--;) {
    var option = elem.options[j];
    if (option.value != '' && $(elem).val() != option.value) {
      $('#' + prefix + option.value).hide();
    }
  }
}
$(function() {
  show_options($('#ldap_setting_group_membership')[0], 'membership_');
  $('#ldap_setting_group_membership')
    .bind('change keyup', function() { show_options(this, 'membership_') });

  show_options($('#ldap_setting_nested_groups')[0], 'nested_');
  $('#ldap_setting_nested_groups')
    .bind('change keyup', function() { show_options(this, 'nested_') });

  $('#base_settings').bind('change keyup', function() {
    var id = $(this).val();
    if (!base_settings[id]) return;

    var hash = base_settings[id];
    for (var k in hash) if (hash.hasOwnProperty(k)) {
      if (k == 'name' || hash[k] == $('#ldap_setting_' + k).val()) continue;

      $('#ldap_setting_' + k).val(hash[k]).change()
        .effect('highlight', {easing: 'easeInExpo'}, 500);
    }
  });
})