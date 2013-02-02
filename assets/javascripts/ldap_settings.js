function show_options(elem, ambit) {
  "use strict";

  var selected = $(elem).val();
  var prefix = '#ldap_attributes div.' + ambit;

  if (selected !== '') {
    $(prefix + '.' + selected).show();
    $(prefix + ':not(.' + selected + ')').hide();
  } else {
    $(prefix).hide();
  }
}

$(function() {
  "use strict";

  show_options($('#ldap_setting_group_membership'), 'membership');
  $('#ldap_setting_group_membership')
    .bind('change keyup', function() { show_options(this, 'membership'); });

  show_options($('#ldap_setting_nested_groups'), 'nested');
  $('#ldap_setting_nested_groups')
    .bind('change keyup', function() { show_options(this, 'nested'); });

  $('#base_settings').bind('change keyup', function() {
    var id = $(this).val();
    if (!base_settings[id]) return;

    var hash = base_settings[id];
    for (var k in hash) if (hash.hasOwnProperty(k)) {
      if (k === 'name' || hash[k] === $('#ldap_setting_' + k).val()) continue;

      $('#ldap_setting_' + k).val(hash[k]).change()
        .effect('highlight', {easing: 'easeInExpo'}, 500);
    }
  });

  $('form[id^="edit_ldap_setting"]').submit(function() {
    var current_tab = $('a[id^="tab-"].selected').attr('id').substring(4);
    $('form[id^="edit_ldap_setting"]').append(
      '<input type="hidden" name="tab" value="' + current_tab + '">'
    );
  });

  $('#commit-test')
    .bind('ajax:before', function() {
      var data = $('form[id^="edit_ldap_setting"]').serialize();
      $(this).data('params', data);
    })
    .bind('ajax:success', function(event, data) {
      $('#test-result').text(data);
    });
});