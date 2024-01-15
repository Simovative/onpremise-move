#!/bin/bash

# script to output excluded tables from the excluded_tables file in a proper format

function errxit() {
	echo "$@"
	exit 1
}

function display_help() {
	echo "Usage: "
	echo "${0} [output-type] <database-name>"
	echo
	echo "[output-type] can be one of the following:"
	echo " mysqldump <database-name>"
	echo "   outputs --ignore-tables switches for mysqldump"
	echo
	echo " mysql <database-name>"
	echo "   outputs sql where statement usable for the show tables command in mysql cli"
	echo
}

# outputs exclude statement suitable for mysqldump
function output_mysqldump() {
	local exclude_file="$1"
	local database_name="$2"
	while read line ; do
		[ "$line" == "" ] && continue
    	echo -n " --ignore-table=${database_name}.${line} "
	done < $exclude_file
	if [ "$line" != "" ] ; then
	  echo -n " --ignore-table=${database_name}.${line} "
	fi
}

# outputs exclude statement suitable for mysql show tables
function output_mysql() {
	local exclude_file="$1"
	local database_name="$2"
	local c=0
	while read line ; do
		[ "$line" == "" ] && continue
    	[ "$c" -ne 0 ] && echo -n " AND"
    	echo -n " tables_in_${database_name} != \"${line}\""
    	((c++))
	done < $exclude_file
	if [ "$line" != "" ] ; then
	  echo -n " tables_in_${database_name} != \"${line}\""
	fi
}

if [ "$#" -ne 2 ] ; then
	(>&2 echo "[FAIL] Missing arguments" )
	display_help
	exit 1
fi

readonly output_type="$1"
readonly database="$2"
readonly script_path="$( cd "$(dirname "$0")" ; pwd -P )"
readonly path_to_excluded_tables_file="${script_path}/excluded_tables"

if [ ! -f "$path_to_excluded_tables_file" ] ; then
	errxit "Cannot find file containing excluded tables"
fi

if [ "$output_type" == "mysqldump" ] ; then
	output_mysqldump "${path_to_excluded_tables_file}" "$database"
fi

if [ "$output_type" == "mysql" ] ; then
	output_mysql "${path_to_excluded_tables_file}" "$database"
fi
