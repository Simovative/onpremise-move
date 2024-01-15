#!/bin/bash

function print_usage_and_exit() {
  echo "Usage: $0 -w <webroot>"
  echo
  echo "This script will switch off the old system during final-step of the cloud-move"
  echo "-h|--help                  print this help text and exit"
  exit 0
}

function errcho() {
	# shellcheck disable=SC2145
	(>&2 echo "[ FAIL ] $@" )
}

function errxit() {
  errcho "$@"
  exit 1
}

function echok() {
  # shellcheck disable=SC2145
  echo "[  OK  ] $@"
}

# parse arguments
[[ "$#" -lt 1 ]] && print_usage_and_exit
while [[ $# -ge 1 ]]; do
  case "$1" in
  -h | --help)
    print_usage_and_exit
    ;;
  esac
  shift
done

a5_cron="/etc/cron.d/ac5"

if [[ -f "$a5_cron" ]]; then
  # deactivate cronjobs
  sed "s/^/#/" $a5_cron | sudo tee $a5_cron
  [ "$?" -ne 0 ] && errxit "failed to disable crontab"
  echok "crontab disabled"
fi

# disable Puppet Agent, because otherwise config would overwritten
sudo puppet agent --disable 'server-umzug'

# enable Maintenance-Seite
if [ -f "/etc/apache2/apache2.conf" ]; then
  echo "SetEnv ENV_MAINTENANCE_MODE 'on'" | sudo tee -a /etc/apache2/apache2.conf
  [ "$?" -ne 0 ] && errxit "failed to write apache2.conf"

  if ! sudo service apache2 reload; then
    errxit "failed to disable the website"
  fi
  echok "Website disabled"
else
  errxit "could not disable Website - apache2.conf not found"
fi

if ! sudo service supervisor stop; then
  errxit "failed to stop supervisor"
fi
echok "supervisor successful stopped"

exit
