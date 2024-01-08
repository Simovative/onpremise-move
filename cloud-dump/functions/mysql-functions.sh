#!/bin/bash

function errcho() {
	(>&2 echo "[ FAIL ] $@" )
}

function errxit() {
	errcho "$@"
	exit 1
}

function echok() {
	echo "[  OK  ] $@"
}

function echoinfo() {
    echo "[ INFO ] $@"
}

function get_from_ini() {
	local needle="$1"
	shift;
	local haystack="$@"
	value=$( echo "$haystack" | grep ${needle} | tr -d ' ' | cut -d '=' -f 2 | tr -d '"' )
	echo ${value} | grep -oE '[^ "]+'
}

function get_database_name_from_webroot() {
  [ -z "$1" ] && errxit "specify webroot as argument 1"
  [ ! -f "${1}/database.ini" ] && return 1
  local connection_info=$( cat ${1}/database.ini )
  get_from_ini "database.name" "$connection_info"
}

function write_mysql_config_file() {
  webroot="$1"
  mysql_config_file="$2"
  [ -z "$webroot" ] && errcho "specify webroot as argument 1" && return 1
  [ -z "$mysql_config_file" ] && errcho "specify mysql_config_file as argument 2" && return 1

  local connection_info_file="${webroot}/database.ini"
  # fetch connection info
  local connection_info=$( cat ${connection_info_file} )
  [[ "$?" -ne 0 ]] && errcho "failed to read ${connection_info_file}" && return 1
  echok "read database connection info file at ${connection_info_file}"

  local sql_host=$( get_from_ini "database.server"   "$connection_info" )
  local sql_user=$( get_from_ini "database.user"     "$connection_info" )
  local sql_pass=$( get_from_ini "database.password" "$connection_info" )
  [[ -z "${sql_host}" ]] && errcho "failed to parse server hostname from ${connection_info_file}" && return 1
  [[ -z "${sql_user}" ]] && errcho "failed to parse database username from ${connection_info_file}" && return 1
  [[ -z "${sql_pass}" ]] && errcho "failed to parse database password from ${connection_info_file}" && return 1
  echok "parsed database.ini"

  echo -e "[client]\nuser=\"${sql_user}\"\npassword=\"${sql_pass}\"\nhost=\"${sql_host}\"\ndefault-character-set=utf8" > ${mysql_config_file}
  echok "wrote mysql config file to ${mysql_config_file}"
}
