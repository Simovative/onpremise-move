#!/bin/bash

function print_usage_and_exit() {
  echo "Usage: ./apply-dump-to-db.sh [-h] -c -d"
  echo
  echo "This script will apply a dump created with the dump-db.sh to a database."
  echo
  echo "Available options:"
  echo
  echo "-h|--help                   print this help text and exit"
  echo "-c|--config-file|--config   the config file with the database credentials"
  echo "-d|--database-name          the database name you want to apply the dump to"
  echo
  echo "Your config file must have the following layout:"
  echo
  echo "[client]"
  echo "user=\"my_user\""
  echo "password=\"my_password\""
  echo "host=\"my_host\""
  exit 0
}

[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]] ; do
  case "$1" in
    -c|--config-file|--config)
      mysql_config="$2"
      shift
    ;;
    -d|--database|--database-name)
      dbname="$2"
      shift
    ;;
    -h|--help)
      print_usage_and_exit
    ;;
  esac
  shift
done
if [ -z "$dbname" ] ; then
  echo "missing database: use -d or --database or --database-name to set"
  exit 1
fi

if [ ! -f "${mysql_config}" ] ; then
  echo "missing mysql config file at ${mysql_config}"
  exit 2
fi

if [ ! -d "schema" ] ; then
  echo "missing directory schema"
  exit 3
fi

if [ ! -d "data" ] ; then
  echo "missing directory data"
  exit 3
fi

if [ ! -d "post" ] ; then
  echo "missing directory post"
  exit 3
fi

readonly location="$( cd "$(dirname "$0")" ; pwd -P )"
readonly path_to_excluded_tables_file="${location}/get_excluded_tables.sh"

ignored_tables=$( "${path_to_excluded_tables_file}" mysql "${dbname}")
if [ -z "${ignored_tables}" ] ; then
	echo "Error - Cannot build mysql query"
	exit 3
fi
tables=$(mysql --defaults-extra-file=${mysql_config} ${dbname} -e "SHOW FULL tables WHERE Table_Type != 'VIEW' AND (${ignored_tables})" | awk '{ print $1}' | grep -v '^Tables' )
echo "Used database is ${dbname}"
#echo ${tables}
# make sure tables exist
if [ "$tables" == "" ]
then
	echo "No table found in ${dbname} database!"
fi

# create file with sql scripts
echo "SET foreign_key_checks = 0;" > schema/delete-tables.sql
for t in $tables
do
	echo "drop table if exists "'`'"$t"'`'";" >> schema/delete-tables.sql
done
echo "SET foreign_key_checks = 1;" >> schema/delete-tables.sql

# drop views if exist
views=$(mysql --defaults-extra-file=${mysql_config} ${dbname} -e "SHOW FULL tables WHERE Table_Type = 'VIEW' AND (${ignored_tables})" | awk '{ print $1}' | grep -v '^Tables' )
if [ "$views" != "" ]
then
  for view in $views
  do
    echo "drop view if exists "'`'"$view"'`'";" >> schema/delete-tables.sql
  done
fi

mysql_command="mysql --defaults-extra-file=${mysql_config} ${dbname} "
out=$( echo ";" | $mysql_command 2>&1 )
if [[ "$?" -ne 0 ]] ; then
  echo "failed to connect to database: $out"
  exit 4
fi

echo "deleting database"
mysql --defaults-extra-file=${mysql_config} ${dbname} < schema/delete-tables.sql
if [ $? -eq 0 ] ; then
  echo " OK"
else
  echo " FAIL. Stopping process."
  exit 5
fi
echo "database deleted"
mkdir -p imported

echo "importing schema"
mysql --defaults-extra-file=${mysql_config} ${dbname} < schema/schema.sql
if [ $? -eq 0 ] ; then
  echo " OK"
else
  echo " FAIL. Stopping process."
  exit 5
fi

for file in $( ls -1 data/*sql ) ; do
  echo -n "importing $file "
  mysql --defaults-extra-file=${mysql_config} ${dbname} < ${file}
  if [ $? -eq 0 ] ; then
    echo " OK"
    mv ${file} imported/
  else
    echo " FAIL"
    echo "${file}" >> failed_files
  fi
done

for file in $( ls -1 post/*sql ) ; do
  echo -n "importing $file "
  mysql --defaults-extra-file=${mysql_config} ${dbname} < ${file}
  if [ $? -eq 0 ] ; then
    echo " OK"
  else
    echo " FAIL"
    echo "${file}" >> failed_files
  fi
done
if [[ -f "failed_files" ]]; then
    echo "$(pwd)/failed_files exists. Something went wrong please check failed_files and handle appropriate, and then continue with the process"
    exit 1
fi
