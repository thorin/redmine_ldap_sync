#/bin/bash
set -e # exit if any command fails

setenv() {
  export RAILS_ENV=test
  export RUBYOPT=-W1
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
            export REDMINE_TARBALL=https://github.com/edavis10/redmine/archive/$REDMINE.tar.gz
            ;;
    *.*-stable) export PATH_TO_PLUGINS=./plugins # for redmine 2.x-stable
            export REDMINE_SVN_REPO=http://svn.redmine.org/redmine/branches/$REDMINE
            ;;
    master) export PATH_TO_PLUGINS=./plugins
            export REDMINE_SVN_REPO=http://svn.redmine.org/redmine/trunk/
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
    pushd $TARGET 1> /dev/null
    git checkout $REDMINE_GIT_TAG
    popd 1> /dev/null
  elif [ -n "${REDMINE_HG_REPO}" ]; then
    hg clone -r $REDMINE_HG_TAG $QUIET $REDMINE_HG_REPO $TARGET
  elif [ -n "${REDMINE_SVN_REPO}" ]; then
    svn co $QUIET $REDMINE_SVN_REPO $TARGET
  else
    mkdir -p $TARGET
    wget $REDMINE_TARBALL -O- | tar -C $TARGET -xz --strip=1 --show-transformed -f -
  fi
}

install_plugin_gemfile()
{
  setenv

  mkdir $REDMINE_DIR/$PATH_TO_PLUGINS/redmine_ldap_sync
  ln -s "$PATH_TO_LDAPSYNC/config/Gemfile.travis" "$REDMINE_DIR/$PATH_TO_PLUGINS/redmine_ldap_sync/Gemfile"

  if [ "$RUBY_VERSION"  == "1.8.7" ]; then
    sed -i.bak '/test-unit/d' "$REDMINE_DIR/Gemfile"
  fi
}

prepare_redmine()
{
  setenv

  pushd $REDMINE_DIR 1> /dev/null

  trace 'Database migrations'
  bundle exec rake db:migrate $TRACE

  trace 'Load defaults'
  bundle exec rake redmine:load_default_data REDMINE_LANG=en $TRACE

  trace 'Session token'
  bundle exec rake generate_secret_token $TRACE

  popd 1> /dev/null
}

prepare_plugin()
{
  setenv

  pushd $REDMINE_DIR 1> /dev/null

  ln -s $PATH_TO_LDAPSYNC/* $PATH_TO_PLUGINS/redmine_ldap_sync

  trace 'Prepare plugins'
  bundle exec rake redmine:plugins NAME=redmine_ldap_sync $TRACE

  popd 1> /dev/null
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

  pushd $REDMINE_DIR 1> /dev/null

  if [ "$REDMINE" == "master" ] && [ "$RUBY_VERSION"  == "2.4.3" ]; then
    bundle exec rake redmine:plugins:ldap_sync:coveralls:test $TRACE
  else
    bundle exec rake redmine:plugins:ldap_sync:test $TRACE
  fi

  popd 1> /dev/null
}

test_uninstall()
{
  setenv

  pushd $REDMINE_DIR 1> /dev/null

  bundle exec rake $TRACE redmine:plugins NAME=redmine_ldap_sync VERSION=0

  popd 1> /dev/null
}

case "$1" in
  "clone_redmine") shift; clone_redmine $@;;
  "install_plugin_gemfile") shift; install_plugin_gemfile $@;;
  "prepare_redmine") shift; prepare_redmine $@;;
  "prepare_plugin") shift; prepare_plugin $@;;
  "start_ldap") shift; start_ldap $@;;
  "run_tests") shift; run_tests $@;;
  "test_uninstall") shift; test_uninstall $@;;
  *) echo "clone_redmine; install_plugin_gemfile; prepare_redmine; prepare_plugin; start_ldap; run_tests; test_uninstall";;
esac
