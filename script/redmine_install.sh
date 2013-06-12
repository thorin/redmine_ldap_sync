#/bin/bash

if [[ -z "$REDMINE_VER" ]]; then
  echo "You have not set REDMINE_VER"
  exit 1
fi

if [[ ! "$WORKSPACE" = /* ]] ||
   [[ ! "$PATH_TO_REDMINE" = /* ]] ||
   [[ ! "$PATH_TO_LDAPSYNC" = /* ]];
then
  echo "You should set"\
       " REDMINE_VER, WORKSPACE, PATH_TO_REDMINE, PATH_TO_LDAPSYNC"\
       " environment variables"
  echo "You set:"\
       "$WORKSPACE"\
       "$PATH_TO_REDMINE"\
       "$PATH_TO_LDAPSYNC"
  exit 1;
fi

export RAILS_ENV=test
export IN_RBL_TESTENV=true

case $REDMINE_VER in
  1.4.*)  export PATH_TO_PLUGINS=./vendor/plugins # for redmine < 2.0
          export GENERATE_SECRET=generate_session_store
          export MIGRATE_PLUGINS=db:migrate_plugins
          export REDMINE_TARBALL=https://github.com/edavis10/redmine/archive/$REDMINE_VER.tar.gz
          ;;
  2.*)    export PATH_TO_PLUGINS=./plugins # for redmine 2.0
          export GENERATE_SECRET=generate_secret_token
          export MIGRATE_PLUGINS=redmine:plugins:migrate
          export REDMINE_TARBALL=https://github.com/edavis10/redmine/archive/$REDMINE_VER.tar.gz
          ;;
  master) export PATH_TO_PLUGINS=./plugins
          export GENERATE_SECRET=generate_secret_token
          export MIGRATE_PLUGINS=redmine:plugins:migrate
          export REDMINE_GIT_REPO=git://github.com/edavis10/redmine.git
          export REDMINE_GIT_TAG=master
          ;;
  v3.8.0) export PATH_TO_PLUGINS=./vendor/chilliproject_plugins
          export GENERATE_SECRET=generate_session_store
          export MIGRATE_PLUGINS=db:migrate:plugins
          export REDMINE_TARBALL=https://github.com/chiliproject/chiliproject/archive/$REDMINE_VER.tar.gz
          ;;
  *)      echo "Unsupported platform $REDMINE_VER"
          exit 1
          ;;
esac

export BUNDLE_GEMFILE=$PATH_TO_REDMINE/Gemfile

clone_redmine()
{
  set -e # exit if clone fails
  rm -rf $PATH_TO_REDMINE
  if [ ! "$VERBOSE" = "yes" ]; then
    QUIET=--quiet
  fi
  if [ -n "${REDMINE_GIT_TAG}" ]; then
    git clone -b $REDMINE_GIT_TAG --depth=100 $QUIET $REDMINE_GIT_REPO $PATH_TO_REDMINE
    cd $PATH_TO_REDMINE
    git checkout $REDMINE_GIT_TAG
  else
    mkdir -p $PATH_TO_REDMINE
    wget $REDMINE_TARBALL -O- | tar -C $PATH_TO_REDMINE -xz --strip=1 --show-transformed -f -
  fi
}

run_tests()
{
  # exit if tests fail
  set -e

  cd $PATH_TO_REDMINE

  if [ "$VERBOSE" = "yes" ]; then
    TRACE=--trace
  fi

  if [ "$REDMINE_VER" == "master" ] && [ "$(ruby -e 'print RUBY_VERSION')"  == "1.9.3" ]; then
    bundle exec rake redmine:plugins:ldap_sync:coveralls:test $TRACE
  else
    bundle exec rake redmine:plugins:ldap_sync:test $TRACE
  fi
}

uninstall()
{
  set -e # exit if migrate fails
  cd $PATH_TO_REDMINE
  # clean up database
  if [ "$VERBOSE" = "yes" ]; then
    TRACE=--trace
  fi
  bundle exec rake $TRACE $MIGRATE_PLUGINS NAME=redmine_ldap_sync VERSION=0
}

run_install()
{
  # exit if install fails
  set -e

  # cd to redmine folder
  cd $PATH_TO_REDMINE
  echo current directory is `pwd`

  # copy database.yml
  cp $WORKSPACE/database.yml config/

  # install gems
  mkdir -p vendor/bundle
  bundle install --without development rmagick --path vendor/bundle

  if [ "$VERBOSE" = "yes" ]; then echo 'Gems installed'; fi

  if [ "$VERBOSE" = "yes" ]; then
    export TRACE=--trace
  fi

  # run redmine database migrations
  if [ "$VERBOSE" = "yes" ]; then echo 'Migrations'; fi
  bundle exec rake db:migrate $TRACE

  # install redmine database
  if [ "$VERBOSE" = "yes" ]; then echo 'Load defaults'; fi
  bundle exec rake redmine:load_default_data REDMINE_LANG=en $TRACE

  if [ "$VERBOSE" = "yes" ]; then echo 'Tokens'; fi
  # generate session store/secret token
  bundle exec rake $GENERATE_SECRET $TRACE

  ### Install the plugin

  # create a link to the ldap_sync plugin, but avoid recursive link.
  if [ -L "$PATH_TO_PLUGINS/redmine_ldap_sync" ]; then rm "$PATH_TO_PLUGINS/redmine_ldap_sync"; fi
  ln -s "$PATH_TO_LDAPSYNC" "$PATH_TO_PLUGINS/redmine_ldap_sync"

  # install plugin gems
  bundle install --without development rmagick --path vendor/bundle

  # install redmine database
  if [ "$VERBOSE" = "yes" ]; then echo 'Load defaults'; fi
  bundle exec rake redmine:plugins NAME=redmine_ldap_sync  $TRACE

  if [ "$VERBOSE" = "yes" ]; then echo 'Done!'; fi
}

while getopts :irtu opt
do case "$opt" in
  r)  clone_redmine; exit 0;;
  i)  run_install;  exit 0;;
  t)  run_tests $2;  exit 0;;
  u)  uninstall;  exit 0;;
  [?]) echo "i: install; r: clone redmine; t: run tests; u: uninstall";;
  esac
done