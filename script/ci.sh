#/bin/bash
set -e # exit if any command fails

setenv() {
  export RAILS_ENV=test
  export IN_RBL_TESTENV=true
  export PATH_TO_LDAPSYNC=$(pwd)
  export RUBY_VERSION=$(ruby -e 'print RUBY_VERSION')
  if [[ -z "$REDMINE" ]]; then
    echo "You have not set REDMINE"
    exit 1
  fi
  if [ "$VERBOSE" = "yes" ]; then export TRACE=--trace; fi
  if [ ! "$VERBOSE" = "yes" ]; then export QUIET=--quiet; fi

  case $REDMINE in
    2.*.*)  export PATH_TO_PLUGINS=./plugins # for redmine 2.x.x
            export GENERATE_SECRET=generate_secret_token
            export MIGRATE_PLUGINS=redmine:plugins
            export REDMINE_TARBALL=https://github.com/edavis10/redmine/archive/$REDMINE.tar.gz
            ;;
    2.*-stable) export PATH_TO_PLUGINS=./plugins # for redmine 2.x-stable
            export GENERATE_SECRET=generate_secret_token
            export MIGRATE_PLUGINS=redmine:plugins
            export REDMINE_SVN_REPO=http://svn.redmine.org/redmine/branches/$REDMINE
            ;;
    master) export PATH_TO_PLUGINS=./plugins
            export GENERATE_SECRET=generate_secret_token
            export MIGRATE_PLUGINS=redmine:plugins
            export REDMINE_SVN_REPO=http://svn.redmine.org/redmine/trunk/
            ;;
    v3.8.0) export PATH_TO_PLUGINS=./vendor/chiliproject_plugins
            export GENERATE_SECRET=generate_session_store
            export MIGRATE_PLUGINS=db:migrate:plugins
            export REDMINE_TARBALL=https://github.com/chiliproject/chiliproject/archive/$REDMINE.tar.gz
            export RUBYGEMS=1.8.29
            ;;
    *)      echo "Unsupported platform $REDMINE"
            exit 1
            ;;
  esac
}

extract_args() {
  while :; do
    case "$1" in
      --target) export TARGET="$2"; shift; shift;;
      -*) echo "Invalid argument $1"; exit 2;;
      *) break;;
    esac
  done
}

trace() {
  if [ "$VERBOSE" = "yes" ]; then echo $@; fi
}

clone_redmine()
{
  setenv; extract_args $@

  if [[ -z "$TARGET" ]]; then
    echo "You have not set a target directory"; exit 1
  fi

  rm -rf $TARGET
  if [ -n "${REDMINE_GIT_REPO}" ]; then
    git clone -b $REDMINE_GIT_TAG --depth=100 $QUIET $REDMINE_GIT_REPO $TARGET
    pushd $TARGET > /dev/null
    git checkout $REDMINE_GIT_TAG
    popd
  elif [ -n "${REDMINE_HG_REPO}" ]; then
    hg clone -r $REDMINE_HG_TAG $QUIET $REDMINE_HG_REPO $TARGET
  elif [ -n "${REDMINE_SVN_REPO}" ]; then
    svn co $QUIET $REDMINE_SVN_REPO $TARGET
  else
    mkdir -p $TARGET
    wget $REDMINE_TARBALL -O- | tar -C $TARGET -xz --strip=1 --show-transformed -f -
  fi

  # Temporarily pin down database_cleaner for bug with sqlite, see https://github.com/bmabey/database_cleaner/issues/224
  sed -ri 's/gem "database_cleaner"/gem "database_cleaner", "< 1.1.0"/' $TARGET/Gemfile
}

install_plugin_gemfile()
{
  setenv

  mkdir $REDMINE_DIR/$PATH_TO_PLUGINS/redmine_ldap_sync
  ln -s "$PATH_TO_LDAPSYNC/Gemfile" "$REDMINE_DIR/$PATH_TO_PLUGINS/redmine_ldap_sync/Gemfile"
}

bundle_install()
{
  if [ -n "${RUBYGEMS}" ]; then
    rvm rubygems ${RUBYGEMS}
  fi
  pushd $REDMINE_DIR > /dev/null
  for i in {1..3}; do
    gem install bundler --no-rdoc --no-ri && \
    bundle install --gemfile=./Gemfile --path vendor/bundle --without development rmagick && break
  done && popd
}

prepare_redmine()
{
  setenv

  pushd $REDMINE_DIR > /dev/null

  trace 'Database migrations'
  bundle exec rake db:migrate $TRACE

  trace 'Load defaults'
  bundle exec rake redmine:load_default_data REDMINE_LANG=en $TRACE

  trace 'Session token'
  bundle exec rake $GENERATE_SECRET $TRACE

  popd
}

prepare_plugin()
{
  setenv

  pushd $REDMINE_DIR > /dev/null

  rm $PATH_TO_PLUGINS/redmine_ldap_sync/Gemfile
  ln -s $PATH_TO_LDAPSYNC/* $PATH_TO_PLUGINS/redmine_ldap_sync

  trace 'Prepare plugins'
  bundle exec rake $MIGRATE_PLUGINS NAME=redmine_ldap_sync $TRACE

  popd
}

start_ldap()
{
  export LDAPNOINIT=yes

  LDAPBASE=$(mktemp --tmpdir=/tmp -d ldapsyncldap.XXXXX)
  LDAPCONF=test/fixtures/ldap

  if [ -f /etc/openldap/schema/core.schema ]; then
    SCHEMABASE=/etc/openldap/schema
  else
    SCHEMABASE=/etc/ldap/schema
  fi

  echo ${LDAPBASE} > .ldapbase

  mkdir ${LDAPBASE}/db
  cp ${LDAPCONF}/slapd.conf ${LDAPBASE}/

  sed -i "s|/var/run/slapd/slapd.pid|${LDAPBASE}/slapd.pid|" ${LDAPBASE}/slapd.conf
  sed -i "s|/var/run/slapd/slapd.args|${LDAPBASE}/slapd.pid|" ${LDAPBASE}/slapd.conf
  sed -i "s|/var/lib/ldap|${LDAPBASE}/db|" ${LDAPBASE}/slapd.conf
  sed -i "s|/etc/ldap/schema|${SCHEMABASE}|" ${LDAPBASE}/slapd.conf

  nohup slapd -d3 -f ${LDAPBASE}/slapd.conf -h 'ldap://localhost:3389/' &> ${LDAPBASE}/slapd.log &

  # Give LDAP a few seconds to start
  sleep 3

  if [ ! -z "$VERBOSE" ]; then
    cat ${LDAPBASE}/slapd.log
  fi

  ldapadd -x -D 'cn=admin,dc=redmine,dc=org' -w password -H 'ldap://localhost:3389/' -f ${LDAPCONF}/test-ldap.ldif > /dev/null
  trace "LDAP Started"
}

run_tests()
{
  setenv

  pushd $REDMINE_DIR > /dev/null

  if [ "$REDMINE" == "master" ] && [ "$RUBY_VERSION"  == "1.9.3" ]; then
    bundle exec rake redmine:plugins:ldap_sync:coveralls:test $TRACE
  else
    bundle exec rake redmine:plugins:ldap_sync:test $TRACE
  fi

  popd
}

test_uninstall()
{
  setenv

  pushd $REDMINE_DIR > /dev/null

  bundle exec rake $TRACE $MIGRATE_PLUGINS NAME=redmine_ldap_sync VERSION=0

  popd
}

case "$1" in
  "clone_redmine") shift; clone_redmine $@;;
  "install_plugin_gemfile") shift; install_plugin_gemfile $@;;
  "bundle_install") shift; bundle_install $@;;
  "prepare_redmine") shift; prepare_redmine $@;;
  "prepare_plugin") shift; prepare_plugin $@;;
  "start_ldap") shift; start_ldap $@;;
  "run_tests") shift; run_tests $@;;
  "test_uninstall") shift; test_uninstall $@;;
  *) echo "clone_redmine; install_plugin_gemfile; prepare_redmine; prepare_plugin; start_ldap; run_tests; test_uninstall";;
esac
