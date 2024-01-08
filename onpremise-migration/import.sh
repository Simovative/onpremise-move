#!/bin/bash
set -o nounset

readonly location=$( cd "$(dirname "$0")"; pwd -P )

source ../functions/functions.sh

# test with
# cd /home/ltrischberger/development/workspace/cloud-move/deployment
#./import.sh -d awesome.academyfive.net -p ~/development/workspace/cloud-move/cloud-dump/basetables.tar.gz --type preparation -m "mysql://root:root@127.0.0.1/acfive"

function print_usage_and_exit() {
  echo "Usage: ${0} [-h] -e <environment> -d <destination-url> -p <path-to-dump> -t <type>"
  echo
  echo "This script will import a dump to a database"
  echo
  echo "Available options:"
  echo
  echo "-h|--help                  print this help text and exit"
  echo "-d|--destination-url       the destination url where the dump should be imported"
  echo "-p|--path-to-dump          the path to the dumpfile in s3"
  echo "-m|--mysql-connection-url  connection-url to database eg. mysql://user:pass@db.university.intern/database"
  echo "-t|--type                  preparation or final"
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
  -t | --type)
    type="$2"
    shift
    ;;
  -p | --path-to-dump)
    pathToDump="$2"
    shift
    ;;
  -m | --mysql-connection-url)
    mysqlConnectionUrl="$2"
    shift
    ;;
  -h | --help)
    print_usage_and_exit
    ;;
  esac
  shift
done

readonly remoteDir="/tmp/import/${destinationUrl}"

echoinfo "starting"

echoinfo "ensure remote dir exists and is empty: ${remoteDir}":
rm -rf ${remoteDir}
[ "$?" -ne 0 ] && errxit "failed to remove dir: ${remoteDir}"

mkdir -p ${remoteDir}
[ "$?" -ne 0 ] && errxit "failed to create dir: ${remoteDir}"

echoinfo "execute the script"
../onpremise-import/import-dump-to-cloud.sh -p ${pathToDump} -d ${destinationUrl} -t "${type}" -m ${mysqlConnectionUrl}
if [[ "$?" -ne 0 ]] ; then
	errxit "failed to import dump to cloud"
fi
echok "dump imported successfully"

echoinfo "Please execute 'source /etc/profile; export AC5_TENANT=${destinationUrl}; sudo -E -u www-data php /srv/a5_source/httpdocs/bin/cli.php update:update' on one of the containers"

echok "import done"
