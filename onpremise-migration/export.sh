#!/bin/bash
set -o nounset

readonly location=$( cd "$(dirname "$0")"; pwd -P )
source ${location}/../functions/functions.sh

function print_usage_and_exit() {
  echo "Usage: ${0} [-h] -w -t"
  echo
  echo "This script will dump the database from a standalone source system ready to be imported to a onpremise-system"
  echo
  echo "Available options:"
  echo
  echo "-h|--help               print this help text and exit"
  echo "-w|--web-root           path to webroot: /var/www/vhosts/a5.university.net/httpdocs"
  echo "-t|--type               preparation or final"
  exit 0
}

[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]] ; do
  case "$1" in
    -w|--web-root)
      readonly webroot="$2"
      shift
    ;;
    -t|--type)
      readonly type="$2"
      shift
    ;;
    -h|--help)
      print_usage_and_exit
    ;;
  esac
  shift
done
echok "parsed arguments"

path=/tmp/cloud-move
mkdir -p ${path} 2>/dev/null
[ "$?" -ne 0 ] && errxit "cannot create working directory ${path}"
echok "created working directory ${path}"

../cloud-dump/create-dump.sh -w ${webroot} -t ${type} -p ${path}
[ "$?" -ne 0 ] && errxit "dump failed"
echok "dump completed"

source ${location}/../cloud-dump/functions/mysql-functions.sh
database_name=$( get_database_name_from_webroot ${webroot} )

echoinfo "packing dump for database ${database_name}"
[ ! -d ${location}/../cloud-dump/${database_name} ] && errxit "cannot find dump folder ${database_name} in ${location}/../cloud-dump/${database_name}"
(cd ${location}/../cloud-dump/${database_name} && tar czf ../${database_name}.tar.gz . )
[ "$?" -ne 0 ] && errxit "failed to pack dump"
echok "prepared tarball"

echok "export of database complete and located at: ${location}/../cloud-dump/${database_name}.tar.gz"
