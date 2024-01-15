#!/bin/bash
set -o nounset

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

function echoinfo() {
    # shellcheck disable=SC2145
    echo "[ INFO ] $@"
}

function failOnError() {
    if [[ "$1" -ne 0 ]] ; then
      errxit "${2}"
    fi
}

function exec_remote_ssh_command() {
  local remote="$1"
  shift
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o ServerAliveInterval=60 ${remote} "$@"
}

function get_aws_account_credentials() {
  case $1 in
	"dev")
	  aws_account_id="478224300327"
	  aws_role_name="administrator"
	  role_session_name="deployment.user-simovative-development-Administrator"
	  server="bastion.a5cloud-dev.net"
	;;
  "preview")
    aws_account_id="124339180352"
    aws_role_name="administrator"
    role_session_name="deployment.user-simovative-preview-Administrator"
    server="bastion.a5cloud-preview.net"
  ;;
  "production")
    aws_account_id="542125123399"
    aws_role_name="academy.production.administrator"
    role_session_name="deployment.user-simovative-production-Administrator"
    server="bastion.a5cloud-production.net"
  ;;
  "iubh")
    aws_account_id="584873241708"
    aws_role_name="academy.iubh.administrator"
    role_session_name="deployment.user-simovative-iubh-Administrator"
    server="bastion.a5cloud-iubh.net"
  ;;
  *)
    echo "environment not found"
    exit 1
  ;;
  esac
}

function get_token_bundle_for_assume_role() {
  if [ -z "$1" ] ; then
    local duration=28800
  else
    local duration="$1"
  fi
  ASSUME_ROLE_TOKEN_BUNDLE=$(aws sts assume-role --output text --profile default --duration-seconds $duration --role-arn arn:aws:iam::${aws_account_id}:role/${aws_role_name} --role-session-name "${role_session_name}" | tail -1)
  returnCodeRoleAssume=$?
  # check if role assume successful
  if [ -z "$ASSUME_ROLE_TOKEN_BUNDLE" ] || [ $returnCodeRoleAssume -ne 0 ]; then
    echo "Role assume failed"
    echo "return code: $returnCodeRoleAssume"
    exit 1
  fi
  echo "$ASSUME_ROLE_TOKEN_BUNDLE"
}
