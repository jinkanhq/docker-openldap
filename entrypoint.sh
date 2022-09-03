#!/bin/bash
set -e

if [ $# -ge 1 ]; then
  exec "$@"
  exit 0
fi

SLAPD_MODULE_PATH=/usr/local/libexec/openldap
SLAPD_ETC_DIRECTORY=/usr/local/etc/openldap
SLAPD_DATA_DIRECTORY=/usr/local/var/openldap-data
export LD_LIBRARY_PATH=/usr/local/lib:$SLAPD_MODULE_PATH
export PATH="${PATH}:/usr/local/sbin:/usr/local/libexec"
SLAPD_CONFIG_DIRECTORY=/usr/local/etc/slapd.d

# Basic configuration
DEBUG=${DEBUG:-false}
LDAP_DOMAIN="${LDAP_DOMAIN:-example.com}"
LDAP_DOMAIN_COMPONENTS=($(echo $LDAP_DOMAIN | tr "." "\n"))
LDAP_ROOT_CN="${LDAP_ROOT_DN:-admin}"
LDAP_ROOT_PASSWORD="${LDAP_ROOT_PASSWORD:-admin}"
LDAP_ROOT_DN="cn=${LDAP_ROOT_CN}"
LDAP_SUFFIX=""
LDAP_ORGANIZATION=${LDAP_ORGANIZATION:-Example}
LDAP_DEBUG_LEVEL=${LDAP_DEBUG_LEVEL:-stats}

for component in ${LDAP_DOMAIN_COMPONENTS[@]}; do
  LDAP_SUFFIX="${LDAP_SUFFIX},dc=${component}"
  LDAP_ROOT_DN="${LDAP_ROOT_DN},dc=${component}"
done
LDAP_SUFFIX=${LDAP_SUFFIX:1}
LDAP_ROOT_PASSWORD=$(slappasswd -o module-load=argon2 -h {ARGON2} -s $LDAP_ROOT_PASSWORD)

# TLS configuration
TLS_INTERMEDIATE_CIPHER_SUITE="ECDHE-ECDSA-AES128-GCM-SHA256:\
ECDHE-RSA-AES128-GCM-SHA256:\
ECDHE-ECDSA-AES256-GCM-SHA384:\
ECDHE-RSA-AES256-GCM-SHA384:\
ECDHE-ECDSA-CHACHA20-POLY1305:\
ECDHE-RSA-CHACHA20-POLY1305:\
DHE-RSA-AES128-GCM-SHA256:\
DHE-RSA-AES256-GCM-SHA384"
DEFAULT_SSF="ssf=128"
LDAP_TLS_ENABLED="${LDAP_TLS_ENABLED:-false}"
LDAP_TLS_CA_FILE=${LDAP_TLS_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}
LDAP_TLS_CRT_FILE=${LDAP_TLS_CRT_FILE}
LDAP_TLS_KEY_FILE=${LDAP_TLS_KEY_FILE}
LDAP_TLS_DHPARAM_FILE=${LDAP_TLS_DHPARAM_FILE:-$SLAPD_ETC_DIRECTORY/dhparam}
LDAP_TLS_CIPHER_SUITE=${LDAP_TLS_CIPHER_SUITE:-${TLS_INTERMEDIATE_CIPHER_SUITE}}
LDAP_TLS_SSF=${LDAP_TLS_SSF:-${DEFAULT_SSF}}
LDAP_TLS_VERIFY_CLIENT=${LDAP_TLS_VERIFY_CLIENT:-never}

debug() {
  if [ $DEBUG == "true" ]; then
    echo -e "\033[33m[DEBUG]\033[0m $1"
  fi
}

error() {
  echo -e "\033[31m[ERROR]\033[0m $1"
  exit 1
}

mask_argon2() {
  ARGON2_PARTS=($(echo $LDAP_ROOT_PASSWORD | tr "\$" "\n"))
  echo "${ARGON2_PARTS[0]}\$${ARGON2_PARTS[1]}\$${ARGON2_PARTS[2]}\$${ARGON2_PARTS[3]}\$********"
}

get_mdb_dn() {
  echo $(slapcat -n 0 -a '(objectClass=olcDatabaseConfig)' -F $SLAPD_CONFIG_DIRECTORY | grep -oP "(?<=dn: )(.+)mdb(.+)")
}

get_mdb_dbnum() {
  echo $(slapcat -n 0 -a '(objectClass=olcDatabaseConfig)' -F $SLAPD_CONFIG_DIRECTORY | grep -oP "(?<=dn: olcDatabase=\{)(.+)(?=\}mdb)")
}

init_slapd_organization() {
  cat > $SLAPD_ETC_DIRECTORY/org.ldif <<EOF
dn: ${LDAP_SUFFIX}
objectclass: dcObject
objectclass: organization
o: ${LDAP_ORGANIZATION}
dc: ${LDAP_DOMAIN_COMPONENTS[0]}
EOF
  debug "Init organization \"${LDAP_ORGANIZATION}\" with dn: ${LDAP_SUFFIX} and dc: ${LDAP_DOMAIN_COMPONENTS[0]}."
  slapadd -n 1 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/org.ldif
  echo $LDAP_SUFFIX > $SLAPD_CONFIG_DIRECTORY/suffix
}

init_slapd_config() {
  # Get directories ready
  mkdir -p $SLAPD_CONFIG_DIRECTORY
  mkdir -p $SLAPD_DATA_DIRECTORY
  mkdir -p /usr/local/var/run
  chmod 700 $SLAPD_CONFIG_DIRECTORY
  chmod 700 $SLAPD_DATA_DIRECTORY

  cat > $SLAPD_ETC_DIRECTORY/slapd.ldif <<EOF
#
# See slapd-config(5) for details on configuration options.
# This file should NOT be world readable.
#
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /usr/local/var/run/slapd.args
olcPidFile: /usr/local/var/run/slapd.pid

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath:  ${SLAPD_MODULE_PATH}
# olcModuleload:  back_mdb.la
olcModuleload:  argon2.la

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

include: file:///usr/local/etc/openldap/schema/core.ldif
include: file:///usr/local/etc/openldap/schema/cosine.ldif
include: file:///usr/local/etc/openldap/schema/inetorgperson.ldif
include: file:///usr/local/etc/openldap/schema/nis.ldif

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend

dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 1073741824
olcSuffix: ${LDAP_SUFFIX}
olcRootDN: ${LDAP_ROOT_DN}
olcRootPW: ${LDAP_ROOT_PASSWORD}
olcDbDirectory: ${SLAPD_DATA_DIRECTORY}
olcDbIndex: objectClass eq
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,givenName,displayName pres,eq,approx,sub
olcAccess: to attrs=userPassword
  by self write
  by anonymous auth
  by * none
olcAccess: to *
  by self write
  by * read

dn: olcDatabase=monitor,cn=config
objectClass: olcDatabaseConfig
olcDatabase: monitor
olcRootDN: cn=config
olcMonitoring: FALSE
EOF

  cat > /usr/local/etc/openldap/tls.ldif <<EOF
dn: cn=config
changetype: modify
add: olcSecurity
olcSecurity: ${LDAP_TLS_SSF}
-
add: olcTLSCACertificateFile
olcTLSCACertificateFile: ${LDAP_TLS_CA_FILE}
-
add: olcTLSCertificateFile
olcTLSCertificateFile: ${LDAP_TLS_CRT_FILE}
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${LDAP_TLS_KEY_FILE}
-
add: olcTLSCipherSuite
olcTLSCipherSuite: ${LDAP_TLS_CIPHER_SUITE}
-
add: olcTLSDHParamFile
olcTLSDHParamFile: ${LDAP_TLS_DHPARAM_FILE}
-
add: olcTLSVerifyClient
olcTLSVerifyClient: ${LDAP_TLS_VERIFY_CLIENT}
EOF

  # Protect these ldif files
  chmod 700 $SLAPD_ETC_DIRECTORY/*.ldif
  # Init database
  slapadd -n 0 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/slapd.ldif
  if [ $LDAP_TLS_ENABLED == "true" ]; then
    slapmodify -n 0 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/tls.ldif
    touch $SLAPD_CONFIG_DIRECTORY/tls.enabled
  fi
  init_slapd_organization
}

modify_slapd_config_attribute() {
  if [ $# -lt 3 ]; then
    error "modify_slapd_config_attribute: 3 positional parameters are required. (DN, ATTRIBUTE, VALUE)"
  fi
  DN=$1
  ATTRIBUTE=$2
  VALUE=$3
  cat > $SLAPD_ETC_DIRECTORY/modify.ldif <<EOF
dn: ${DN}
changetype: modify
replace: ${ATTRIBUTE}
${ATTRIBUTE}: ${VALUE}
EOF
  debug "Modify attribute \"${ATTRIBUTE}\" of \"${DN}\" to value \"${VALUE}\"."
  slapmodify -n 0 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/modify.ldif
  rm $SLAPD_ETC_DIRECTORY/modify.ldif
}

delete_slapd_entry() {
  if [ $# -lt 2 ]; then
    error "delete_slapd_entry: 2 positional parameters are required. (DBNUM, DN)"
  fi
  DBNUM=$1
  DN=$2
  cat > $SLAPD_ETC_DIRECTORY/delete.ldif <<EOF
dn: ${DN}
changetype: delete
EOF
  debug "Delete entry \"${DN}\"."
  slapmodify -n $DBNUM -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/delete.ldif
  rm $SLAPD_ETC_DIRECTORY/delete.ldif
}

delete_slapd_config_attribute() {
  if [ $# -lt 2 ]; then
    error "delete_slapd_config_attribute: 2 positional parameters are required. (DN, ATTRIBUTE)"
  fi
  DN=$1
  ATTRIBUTE=$2
  cat > $SLAPD_ETC_DIRECTORY/modify.ldif <<EOF
dn: ${DN}
changetype: modify
delete: ${ATTRIBUTE}
EOF
  debug "Delete attribute \"${DN}\" of \"${DN}\"."
  slapmodify -n 0 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/modify.ldif
  rm $SLAPD_ETC_DIRECTORY/modify.ldif
}

run_slapd() {
  LDAP_HOST="ldap://0.0.0.0:389"
  if [ $LDAP_TLS_ENABLED == "true" ]; then
    LDAP_HOST="${LDAP_HOST} ldaps://0.0.0.0:636"
  fi
  debug "slapd is listening on ${LDAP_HOST}..."
  slapd -F $SLAPD_CONFIG_DIRECTORY -d $LDAP_DEBUG_LEVEL -h "${LDAP_HOST}"
}

if [ "$(ls -A $SLAPD_CONFIG_DIRECTORY 2>/dev/null)" == "" ]; then
  debug "empty config directory"
  init_slapd_config
else
  if [ $LDAP_TLS_ENABLED == "true" ]; then
    modify_slapd_config_attribute "cn=config" olcSecurity $LDAP_TLS_SSF
    modify_slapd_config_attribute "cn=config" olcTLSCACertificateFile $LDAP_TLS_CA_FILE
    modify_slapd_config_attribute "cn=config" olcTLSCertificateFile $LDAP_TLS_CRT_FILE
    modify_slapd_config_attribute "cn=config" olcTLSCertificateKeyFile $LDAP_TLS_KEY_FILE
    modify_slapd_config_attribute "cn=config" olcTLSCipherSuite $LDAP_TLS_CIPHER_SUITE
    modify_slapd_config_attribute "cn=config" olcTLSDHParamFile $LDAP_TLS_DHPARAM_FILE
    modify_slapd_config_attribute "cn=config" olcTLSVerifyClient $LDAP_TLS_VERIFY_CLIENT
  elif [ -f $SLAPD_CONFIG_DIRECTORY/tls.enabled ]; then
    delete_slapd_config_attribute "cn=config" olcSecurity
    delete_slapd_config_attribute "cn=config" olcTLSCACertificateFile
    delete_slapd_config_attribute "cn=config" olcTLSCertificateFile
    delete_slapd_config_attribute "cn=config" olcTLSCertificateKeyFile
    delete_slapd_config_attribute "cn=config" olcTLSCipherSuite
    delete_slapd_config_attribute "cn=config" olcTLSDHParamFile
    delete_slapd_config_attribute "cn=config" olcTLSVerifyClient
    rm $SLAPD_CONFIG_DIRECTORY/tls.enabled
  fi

  MDB_DN=$(get_mdb_dn)
  cat > $SLAPD_ETC_DIRECTORY/mdb.ldif <<EOF
dn: ${MDB_DN}
changetype: modify
replace: olcSuffix
olcSuffix: ${LDAP_SUFFIX}
-
replace: olcRootDN
olcRootDN: ${LDAP_ROOT_DN}
-
replace: olcRootPW
olcRootPW: ${LDAP_ROOT_PASSWORD}
EOF
  debug "Modify attribute \"olcSuffix\" of \"${MDB_DN}\" to value \"${LDAP_SUFFIX}\"."
  debug "Modify attribute \"olcRootDN\" of \"${MDB_DN}\" to value \"${LDAP_ROOT_DN}\"."
  debug "Modify attribute \"olcRootPW\" of \"${MDB_DN}\" to value \"$(mask_argon2 $LDAP_ROOT_PASSWORD)\"."
  slapmodify -n 0 -F $SLAPD_CONFIG_DIRECTORY -l $SLAPD_ETC_DIRECTORY/mdb.ldif
  rm $SLAPD_ETC_DIRECTORY/mdb.ldif

  OLD_LDAP_SUFFIX=$(<$SLAPD_CONFIG_DIRECTORY/suffix)
  delete_slapd_entry $(get_mdb_dbnum) $OLD_LDAP_SUFFIX
  init_slapd_organization
fi

run_slapd
