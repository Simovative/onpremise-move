#!/bin/bash

readonly location=$( cd "$(dirname "$0")"; pwd -P )

function errcho() {
  # shellcheck disable=SC2145
  (echo >&2 "[ FAIL ] $@")
}
function errxit() {
  errcho "$@"
  exit 1
}
function echoinfo() {
    # shellcheck disable=SC2145
    echo "[ INFO ] $@"
}

function parseDatabaseUrl() {
  [[ "$#" -lt 1 ]] && errxit "No databaseUrl provided"
  url=$1
  shift

  # remove the protocol
  protocol="$(echo $url | grep '://' | sed -e's,^\(.*://\).*,\1,g')"
  url=$(echo $url | sed -e s,$protocol,,g)

  # extract the user and password
  userpass="$(echo $url | grep @ | cut -d@ -f1)"
  pass=$(echo $userpass | grep : | cut -d: -f2)
  if [ -n "$pass" ]; then
    user=$(echo $userpass | grep : | cut -d: -f1)
  else
    user=$userpass
  fi

  # extract the host
  hostport=$(echo $url | sed -e s,$userpass@,,g | cut -d/ -f1)
  port=$(echo $hostport | grep : | cut -d: -f2)
  if [ -n "$port" ]; then
    host=$(echo $hostport | grep : | cut -d: -f1)
  else
    host=$hostport
  fi

  # extract the database
  database="$(echo $url | grep / | cut -d/ -f2-)"

  readonly sql_user=$user
  readonly sql_pass=$pass
  readonly sql_host=$host
  readonly sql_name=$database
}

function print_usage_and_exit() {
  echo "Usage: ${0} [-h] -d <destination-url> -p <path-to-dump> -t <type> -m <mysql-url>"
  echo
  echo "This script will download the dump from S3 and generate the domain-post-import-script"
  echo
  echo "Available options:"
  echo
  echo "-h|--help                  print this help text and exit"
  echo "-d|--destination-url url   the destination url where the dump should be imported"
  echo "-p|--path-to-dump          the path to the dumpFolder in s3"
  echo "-t|--type                  preparation or final"
  echo "-m|--mysql-url             mysql url eg. 'mysql://user:pass@dbserver.new' Note: Port will be cut away"
  echo
  exit 0
}

[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]]; do
  case "$1" in
  -d | --destination-url)
    destinationUrl="$2"
    shift
    ;;
  -p | --path-to-dump)
    pathToDump="$2"
    shift
    ;;
  -t|--type)
    type="$2"
    shift
    ;;
  -m|--mysql-url)
    databaseUrl="$2"
    shift
    ;;
  -h | --help)
    print_usage_and_exit
    ;;
  esac
  shift
done

if [ -z "${destinationUrl}" ]; then
  echo "missing destination url: use -d or --destination-url to set this parameter"
  exit 2
fi

if [ -z "${pathToDump}" ]; then
  echo "missing path to dump: use -p or --path-to-dump to set this parameter"
  exit 3
fi

if [ -z "${databaseUrl}" ]; then
  echo "missing mysql url: use -m or --mysql-url to set this parameter"
  exit 4
fi

set -o nounset

echo "Current user is: $(whoami)"

echoinfo "parsing database-url"
parseDatabaseUrl ${databaseUrl}
[ "$?" -ne 0 ] && errxit "parsing database-url failed"
echoinfo "done"

mysql_config_file=${location}/${sql_name}.cnf
echoinfo "writing database-credentials to config file ${mysql_config_file}"
echo -e "[client]\nuser=\"${sql_user}\"\npassword=\"${sql_pass}\"\nhost=\"${sql_host}\"\ndefault-character-set=utf8" > ${mysql_config_file}
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to write ${mysql_config_file}"
fi
echoinfo "done"

echoinfo "fetching dump from ${pathToDump}"
if [ ! -f ${pathToDump} ]; then
  errxit "dump not found: ${pathToDump}"
fi

dumpFolder=/tmp/onpremise-dump
echoinfo "cleaning up working dir: ${dumpFolder}"
rm -rf ${dumpFolder}
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to cleanup working dir: ${dumpFolder}"
fi
mkdir -p ${dumpFolder}
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to create working dir: ${dumpFolder}"
fi

cp ${pathToDump} ${dumpFolder}/dump.tar.gz
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to move dump"
fi

tar -x -z --no-same-owner -f ${dumpFolder}/dump.tar.gz -C ${dumpFolder}/
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to extract dump"
fi

echoinfo "saved dump in ${dumpFolder}"
cd ${dumpFolder} || errxit "Could not access folder ${dumpFolder}"

# check mysql connection
out=$( mysql --defaults-extra-file=${mysql_config_file} -e ";" 2>&1 )
if [[ "$?" -ne 0 ]] ; then
	errxit "remote database credentials invalid: ${out}"
fi

rm "${dumpFolder}/dump.tar.gz"
if [ "${type}" != "final" ]; then
  # preserve domain mapping
  [ -f "${dumpFolder}/post/autogen_cms_domains.sql" ] && rm "${dumpFolder}/post/autogen_cms_domains.sql"
  mysql --defaults-extra-file=${mysql_config_file} ${sql_name} -e "SELECT id, domain FROM cms_domains;" | tail -n +2 | while read pk domain ; do
    echo "UPDATE    cms_domains
          SET       domain = '${domain}',
                    larissa_lib = '/srv/a5_source/httpdocs/lib/',
                    dir_publish='/dev/null'
          WHERE     id = ${pk};" >> ${dumpFolder}/post/autogen_cms_domains.sql
    echo "UPDATE      cms_domains
          INNER JOIN  cms_community
          ON          cms_domains.id = cms_community.domain_id
          SET         cms_community.name = cms_domains.domain,
                      cms_community.url = CONCAT('https://', cms_domains.domain)
          WHERE       cms_domains.domain IS NOT NULL;" >> ${dumpFolder}/post/autogen_cms_domains.sql
  done
  if [[ "$?" -ne 0 ]] ; then
    errxit "generating of domain-post-import-script failed"
  fi

  #update academy url
  cat ${location}/updateUrl.sql | sed "s/local.academyfive.net/${destinationUrl}/g" > ${dumpFolder}/post/updateUrl.sql
  if [[ "$?" -ne 0 ]] ; then
    errxit "failed to update academy url"
  fi
fi

./apply-dump-to-db.sh -c ${mysql_config_file} -d ${sql_name}
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to apply dump"
fi
