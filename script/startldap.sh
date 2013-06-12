#!/bin/bash

export LDAPNOINIT=yes

LDAPBASE=$(mktemp --tmpdir=/tmp -d ldapsyncldap.XXXXX)
LDAPCONF=${PATH_TO_LDAPSYNC}/test/fixtures/ldap

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

nohup slapd -d3 -f ${LDAPBASE}/slapd.conf -h 'ldap://localhost:389/' &> ${LDAPBASE}/slapd.log &

# Give LDAP a few seconds to start
sleep 3

if [ ! -z "$DEBUG" ]; then
  cat ${LDAPBASE}/slapd.log
fi

ldapadd -x -D 'cn=admin,dc=redmine,dc=org' -w password -H 'ldap://localhost:389/' -f ${LDAPCONF}/test-ldap.ldif > /dev/null
echo "LDAP Started"