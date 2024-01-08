#!/bin/bash

readonly location=$( cd "$(dirname "$0")"; pwd -P )
source ${location}/functions/mysql-functions.sh


function print_usage_and_exit() {
  echo "Usage: ./upload.sh [-h] -d -s -w -t -u"
  echo
  echo "This script will tar a database dump and then sync it from a standalone source system to a destination environment in the cloud"
  echo
  echo "Available options:"
  echo
  echo "-h|--help           print this help text and exit"
  echo "-d|--destination    target of the dump: dev, preview, production or iubh"
  echo "-s|--source         the name of the source server"
  echo "-w|--webroot        webroot location for example /var/www/vhosts/test-trunk.academyfive.net/httpdocs"
  echo "-t|--token          location of the token file"
  echo "-u|--url-of-target  the url of the target-system in the cloud"
  exit 0
}

[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]] ; do
  case "$1" in
    -d|--destination)
      readonly destination="$2"
      shift
    ;;
    -s|--source)
      readonly source="$2"
      shift
    ;;
    -w|--webroot|--web-root)
      readonly webroot="$2"
      shift
    ;;
    -t|--token)
      readonly tokenfile="$2"
      shift
    ;;
    -u|--url-of-target)
      readonly url_of_target="$2"
      shift
    ;;
    -h|--help)
      print_usage_and_exit
    ;;
  esac
  shift
done
[ -z "${webroot}" ] && errxit "webroot missing"
[ -z "${source}" ] && errxit "source missing"
[ -z "${destination}" ] && errxit "destination missing"
[ -z "${tokenfile}" ] && errxit "token file missing"
[ ! -f ${tokenfile} ] && errxit "cannot find aws token at ${tokenfile}"
[ -z "${url_of_target}" ] && errxit "url of target system missing"

database_name=$( get_database_name_from_webroot ${webroot} )
[ "$?" -ne 0 ] && errxit "cannot parse database name in ${webroot}"

echoinfo "packing dump for database ${database_name}"
[ ! -d ${location}/${database_name} ] && errxit "cannot find dump folder ${database_name} in /tmp/cloud-sync"
(cd ${location}/${database_name} && tar czf ../${database_name}.tar.gz . )
[ "$?" -ne 0 ] && errxit "failed to pack dump"
echok "prepared tarball"


echoinfo "assuming aws role"
token=$(cat ${tokenfile} )
export AWS_ACCESS_KEY_ID=$(echo "${token}" | awk '{print $2}')
export AWS_SECRET_ACCESS_KEY=$(echo "${token}" | awk '{print $4}')
export AWS_SESSION_TOKEN=$(echo "${token}" | awk '{print $5}')
rm ${tokenfile}
echok "role assume successful"

aws s3 --region=eu-central-1 cp ${location}/${database_name}.tar.gz "s3://simovative-cloud-move-${destination}/${url_of_target}/dump.tar.gz"
[ "$?" -ne 0 ] && rm ${location}/${database_name}.tar.gz 2>/dev/null && rm -rf ${location}/${database_name} && errxit "sync failed"
echok "dump synced to s3://simovative-cloud-move-${destination}/${url_of_target}/dump.tar.gz"

rm ${location}/${database_name}.tar.gz 2>/dev/null
[ -d ${location}/${database_name} ] && rm -rf ${location}/${database_name}
