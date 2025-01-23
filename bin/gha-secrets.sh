#!/usr/bin/env bash

# Utility for creating secrets in Vault for GitHub Actions
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] --secrets <secrets file>" >&2
    echo "This script will create secrets in Vault for GitHub Actions" >&2
}

function args() {
  tls_skip=""
  script_tls_skip=""
  aws_dir="${HOME}/.aws"
  aws_credentials="${aws_dir}/credentials"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  debug_str=""
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--secrets") (( arg_index+=1 ));secrets_file=${arg_list[${arg_index}]};;
          "--debug") set -x; debug_str="--debug";;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
               echo "invalid argument: ${arg_list[${arg_index}]}" >&2
               usage; exit
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

source ${secrets_file}

vault kv put -mount=secrets github-runner-auth github_app_id=${runner_app_id} github_app_installation_id=${runner_app_installation_id} github_app_private_key=${runner_app_private_key}
vault kv put -mount=secrets github-reader-auth github_app_id=${reader_app_id} github_app_installation_id=${reader_app_installation_id} github_app_private_key=${reader_app_private_key}
vault kv put -mount=secrets github-updater-auth github_app_id=${updater_app_id} github_app_installation_id=${updater_app_installation_id} github_app_private_key=${updater_app_private_key}
