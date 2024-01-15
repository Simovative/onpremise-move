#!/bin/bash

readonly location=$( cd "$(dirname "$0")"; pwd -P )
source ../functions/functions.sh

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -p path --destination a5bucket/a5-onpremise.university.net --s3-host s3.university.net -a user:password

Sync academyfive files to S3

Available options:
-h, --help            Print this help and exit

-p, --path            path to academy root without httpdocs eg. /var/www/vhosts/a5.university.net
-d, --destination     a5bucket/<url-of-onpremise-system> example: \"a5bucket/onpremise.academyfive.net\"
--s3-host             hostname / IP address of s3 service
-a, --basicauth       basicauth string, eg. user:password
EOF
  exit
}

parse_params() {
  basicauthstring="minioadmin:minioadmin"
  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -p | --path)
      path="${2-}"
      shift
      ;;
    -d|--destination)
      destination="${2-}"
      shift
      ;;
    --s3-host)
      s3Host="${2-}"
      shift
      ;;
    -a | --auth)
      basicauthstring="${2-}"
      shift
      ;;
    -?*) usage ;;
    *) break ;;
    esac
    shift
  done

  reqParams="";
  # check required params
  [[ -z "${path-}" ]] && reqParams="${reqParams} path"
  [[ -z "${destination-}" ]] && reqParams="${reqParams} destination"
  [[ -z "${s3Host-}" ]] && reqParams="${reqParams} s3Host"
  [[ -z "${basicauthstring-}" ]] && reqParams="${reqParams} basicauthstring"
  [[ -n "${reqParams}" ]] && errxit "Missing required parameter: ${reqParams}" && usage;
  return 0
}

generate_s3cfg() {
    IFS=":"
    read -r ACCESS_KEY SECRET_KEY <<< "$basicauthstring"

    cat << EOF > /tmp/s3cfg
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
host_base = $s3Host
host_bucket = a5bucket.$s3Host
use_https = True
EOF

echok "s3config created at /tmp/s3cfg"
}

get_application_domains_from_database() {
  source "${location}/../cloud-dump/functions/mysql-functions.sh"
  failOnError $? "failed to source mysql-functions.sh current pwd: $(pwd)"
  database_name=$( get_database_name_from_webroot "${path}/httpdocs" )
  failOnError $? "failed to get database name from webroot"

  mysql_config_file="${location}/mysql.cnf"
  write_mysql_config_file "${path}/httpdocs" "${mysql_config_file}"
  failOnError $? "failed to create mysql_config_file"

  query_application_id="SELECT domain FROM cms_layout WHERE aktiv = 1 AND domain NOT in (SELECT domain_id FROM cms_community);"
  domains=$(mysql --defaults-extra-file="${mysql_config_file}" "${database_name}" -sN --execute="${query_application_id}")
  failOnError $? "failed to query application-domains from database"
}

#################### Setup #####################

parse_params "$@"

echoinfo "generate s3-config"
generate_s3cfg
failOnError $? "failed to generate s3 config"

set -o errexit
set -o nounset
set -o pipefail

#################### Let the sync begin #####################

cd ${path}/files || errxit "failed to cd into ${path}/files"

# if there are tmp files not readable for bamboo, aws throws an error code, even if the file is excluded
echoinfo "change permissisons ${path}/files/tmp in order to avoid false error at s3sync"
sudo chmod -R g+r ${path}/files/tmp
echok "done"

echoinfo "sync for ${path}/files to s3://${destination}/ starts"
s3cmd -c /tmp/s3cfg sync --delete-removed --exclude 'tmp/*' --exclude 'temp_files/*' --exclude 'cms/*' ${path}/files/* s3://${destination}/
failOnError $? "failed to sync data to s3"

echok "sync for ${path}/files finishe"

cd ${path}/httpdocs/cms/data || errxit "failed to cd into ${path}/httpdocs/cms/data"

echoinfo "sync for ${path}/httpdocs/cms/data starts"

ls -1 ${path}/httpdocs/cms/data/ | grep -E '^[1-9][0-9]*$'| while read folder; do
  echoinfo "processing folder: ${folder}"
  localPathToDomainFolder="${path}/httpdocs/cms/data/${folder}"
  s3PathToDomainFolder="s3://${destination}/cms/data/${folder}"
  s3cmd -c /tmp/s3cfg sync --exclude --delete-removed "${localPathToDomainFolder}/" --include 'files/*' --exclude 'tmp/*' --exclude 'temp_files/*' --include 'img/*' --include 'system/logo/*' "${s3PathToDomainFolder}/"
  failOnError $? "failed to sync ${localPathToDomainFolder} to ${s3PathToDomainFolder}"

  faviconFile="${localPathToDomainFolder}/favicon.ico"
  if [ -f "${faviconFile}" ]; then
    echoinfo "found favicon.ico file"
    s3cmd -c /tmp/s3cfg put "${faviconFile}" "${s3PathToDomainFolder}/img/favicon.ico"
    failOnError $? "failed to sync ${faviconFile} to ${s3PathToDomainFolder}/img/favicon.ico"
    echoinfo "synced favicon.ico file"
  fi
  customCssFile="${localPathToDomainFolder}/styles/custom.css"
  if [ -f "${customCssFile}" ]; then
    echoinfo "found custom.css file"
    s3cmd -c /tmp/s3cfg put "${customCssFile}" "${s3PathToDomainFolder}/styles/custom.css"
    failOnError $? "failed to sync ${customCssFile} to ${s3PathToDomainFolder}/styles/custom.css"
    echoinfo "synced custom.css file"
  fi
  echok "sucessfully processed folder: ${folder}"
done
echok "sync for ${path}/cms/data finished"

set +o errexit
get_application_domains_from_database
failOnError $? "failed to get domains from database"
set -o errexit
if [[ -z ${domains} ]]; then
  echok "no application domains found for ${mysql_config_file} !"
  exit
fi

echok "found application domains for ${mysql_config_file}"

echoinfo "starting to migrat application layouts"
echo "$domains" | while read domain_id; do
  app_image_path="${path}/httpdocs/cms/data/${domain_id}/"
  query_application_template="SELECT template FROM cms_layout WHERE aktiv = 1 AND domain = ${domain_id} AND name = 'Ganze Seite';"
  template=$(mysql --defaults-extra-file="${mysql_config_file}" "${database_name}" --execute="${query_application_template}")
  failOnError $? "failed to get templates"
  if [[ -n ${template} ]]; then
  re='<img src="([^"]+)"'
  # it is possible for applications with multiple languages to set different language-files
  # We try to unify them for migration into the cloud
  lang_check='\{LANG\}'
    if [[ "$template" =~ $re ]]; then
      headerFileName="${BASH_REMATCH[1]}"
      if [[ "${headerFileName}" =~ $lang_check ]]; then
        header_wildcard_lang=$(echo "${headerFileName}" | sed "s/{LANG}/??/")
        # prevent error while trying to upload multiple files found by wildcard
        pathToRandomApplicationHeaderFile="$(ls ${app_image_path}${header_wildcard_lang}| head -1)"
        s3cmd -c /tmp/s3cfg put "${pathToRandomApplicationHeaderFile}" "s3://${destination}/cms/data/${domain_id}/img/header.jpg"
        failOnError $? "failed to copy header file ${pathToRandomApplicationHeaderFile} to s3://${destination}/cms/data/${domain_id}/img/header.jpg"
      else
        s3cmd -c /tmp/s3cfg put ${app_image_path}${headerFileName} "s3://${destination}/cms/data/${domain_id}/img/header.jpg"
        failOnError $? "failed to copy header file ${app_image_path}${headerFileName} to s3://${destination}/cms/data/${domain_id}/img/header.jpg"
      fi
    fi
  fi
  
done

echoinfo "cleaning up /tmp/s3cfg"
rm /tmp/s3cfg
failOnError $? "unable to cleanup /tmp/s3cfg. Please remove manually"

echok "successfully synced all files"
