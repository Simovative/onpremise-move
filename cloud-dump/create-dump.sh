#!/bin/bash

readonly location=$( cd "$(dirname "$0")" ; pwd -P )
source ${location}/functions/mysql-functions.sh

readonly excluded_tables_preparation="email_tracking
nl_task
nl_config
office365_session_data
office365_setting
office365_calendar_resource_log
office365_calendar
tmp_file"
readonly excluded_tables_final="nl_config
tmp_file"
readonly excluded_tables_preview="settings
settings_schema
settings_schema_sites
notification_banner
digital_signature_document
digital_signature_provider
digital_signature_provider_hpc_dual
moodle_settings
moodle_settings_site
moodle_settings_course_offer_type
nl_config
settings_cronjob
noten_stat_database
email_tracking
nl_task
office365_session_data
office365_setting
office365_calendar_resource_log
office365_calendar
tmp_file"

function print_usage_and_exit() {
  echo "Usage: $0 -w <webroot> -t <type>"
  echo
  echo "This script will create a dump of a database in /tmp/ac5_dump/"
  echo "-h|--help                  print this help text and exit"
  echo "-w|--web-root              path to webroot"
  echo "-t|--type                  the type of dump you want to create (preview/preparation/final)"
  exit 0
}

function get_excluded_tables() {
  case $1 in
	"final")
	  echo ${excluded_tables_final}
	;;
  "preparation")
    echo ${excluded_tables_preparation}
  ;;
  "preview")
    echo ${excluded_tables_preview}
  ;;
  esac
}
function output_mysqldump() {
	local database_name_="$2"
	for table in $( get_excluded_tables $1 ) ; do
		[ "$table" == "" ] && continue
    echo -n " --ignore-table=${database_name_}.${table} "
	done
}

# parse arguments
[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]] ; do
  case "$1" in
    -w|--web-root|--webroot)
      webroot="$2"
      shift
    ;;
    -t|--type)
      type="$2"
      shift
    ;;
    -h|--help)
      print_usage_and_exit
    ;;
  esac
  shift
done
if [ ! -d "${webroot}" ] ; then
  errxit "cannot stat webroot at ${webroot}"
fi
if [ -z "$type" ] ; then
  errxit "missing dump type: use -t or --type to set the type to either final, preparation or preview"
fi
if [[ "$type" != "final" && "$type" != "preparation" && "$type" != "preview" ]] ; then
  errxit "invalid type: type has to be set to either final, preparation or preview"
fi

sql_name=$( get_database_name_from_webroot "${webroot}" )
[ "$?" -ne 0 ] && errxit "cannot find database name in ${webroot}"
mysql_config_file="${location}/${sql_name}.cnf"
write_mysql_config_file "${webroot}" "${mysql_config_file}"
[ "$?" -ne 0 ] && errxit "cannot write mysql config file to ${mysql_config_file}"
echok "wrote mysql config file to ${mysql_config_file}"

mysql_command="mysql --defaults-extra-file=${mysql_config_file} -s -N -A ${sql_name} "
out=$( echo ";" | $mysql_command 2>&1 )
[ "$?" -ne 0 ] && errxit "failed to connect to database: $out"
echok "mysql connection test successful"

dir_schema=${location}/${sql_name}/schema
dir_post=${location}/${sql_name}/post
dir_data=${location}/${sql_name}/data
mkdir -p ${dir_data} ${dir_post} ${dir_schema}
[ "$?" -ne 0 ] && errxit "Cannot create folders at ${location}"
echok "created folders at ${location}"

echoinfo "starting mysqldump"
excluded_tables=$( output_mysqldump ${type} "${sql_name}" )
mysqldump_command="mysqldump --defaults-extra-file=${mysql_config_file} --no-tablespaces --single-transaction"
echoinfo "dumping schema to ${dir_schema}"
set -o errexit
set -o pipefail
${mysqldump_command} ${excluded_tables} ${sql_name} --no-data  | sed -e 's/^\/\*\![0-9]* DEFINER=.*//' | sed "s/\`${sql_name}\`\.//g" > ${dir_schema}/schema.sql
[ "$?" -ne 0 ] && errxit "unable to export schema"
echok "schema dump completed"

for table in $( $mysql_command -e "show tables;" | tail -n +2 ) ; do
  for ex_table in $( get_excluded_tables ${type} ) ; do
		[ "$ex_table" == "" ] && continue
		[ "$ex_table" == "${table}" ] && continue 2
	done
	echo -n "[ INFO ] dumping $table "
	${mysqldump_command} --no-create-info --net_buffer_length=32768 ${sql_name} ${table} > ${dir_data}/${table}.sql
	[ $? -ne 0 ] && errxit "failed"
	echo "success"
done
echok "data dump complete"

if [[ ${type} == "preparation" ]] ; then
  # import newsletter settings while ignoring the rest of the nl_config table
  nl_domain=$( $mysql_command -e "select nl_domain from nl_config limit 1;" )
  [[ ! -z "${nl_domain}" ]] && echo "UPDATE nl_config SET nl_domain = ${nl_domain};" >> ${dir_data}/nl_config.sql
	nl_img_dir=$( $mysql_command -e "select nl_img_dir from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_img_dir = '${nl_img_dir}';" >> ${dir_data}/nl_config.sql
	nl_img_url=$( $mysql_command -e "select nl_img_url from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_img_url = '${nl_img_url}';" >> ${dir_data}/nl_config.sql
	nl_imagick=$( $mysql_command -e "select nl_imagick from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_imagick = '${nl_imagick}';" >> ${dir_data}/nl_config.sql
  nl_list_count=$( $mysql_command -e "select nl_list_count from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_list_count = '${nl_list_count}';" >> ${dir_data}/nl_config.sql
  nl_data_dir=$( $mysql_command -e "select nl_data_dir from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_data_dir = '${nl_data_dir}';" >> ${dir_data}/nl_config.sql
  nl_data_url=$( $mysql_command -e "select nl_data_url from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_data_url = '${nl_data_url}';" >> ${dir_data}/nl_config.sql
  nl_publish_dir=$( $mysql_command -e "select nl_publish_dir from nl_config limit 1;" )
	echo "UPDATE nl_config SET nl_publish_dir = '${nl_publish_dir}';" >> ${dir_data}/nl_config.sql
  # import newsletter-stuff
  ${mysqldump_command} ${sql_name} email_tracking nl_task > ${dir_data}/nl_task_email_tracking.sql
    # prevent newsletter-stuff from being sent
    echo "UPDATE email_tracking SET dispatch_status = 1 WHERE dispatch_status IN (0, 2);" >> ${dir_data}/nl_task_email_tracking.sql
    echo "UPDATE nl_task SET status = 1 WHERE status IN (0, 2);" >> ${dir_data}/nl_task_email_tracking.sql

    echok "added preparation post import updates"
fi

cp ${location}/post/*.sql ${dir_post}/
echok "added additional post import scripts"

cp ${location}/apply-dump-to-db.sh ${location}/${sql_name}
cp ${location}/get_excluded_tables.sh ${location}/${sql_name}
echok "added import script"

rm ${mysql_config_file} 2>/dev/null

for table in $( get_excluded_tables ${type} ) ; do
	[ "$table" == "" ] && continue
   echo "${table}" >> ${location}/${sql_name}/excluded_tables
done
echok "excluded_tables file created with content:"
cat "${location}/${sql_name}/excluded_tables"

echok "dump completed at ${location}/${sql_name}"
