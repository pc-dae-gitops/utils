#!/usr/bin/env bash

# Capture modified and deleted files

set -euo pipefail

source /home/runner/bin/trap.sh

function usage()
{
  echo "usage ${0} [--debug] [--plan-only] " >&2
  echo "This script get details of files deleted and modified in order to determine which environments to execute terraform for" >&2
}

function args() {
  debug=""
  curl_debug="-s"
  op=""
  verbose=""
  upgrade=""

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
      "--debug") debug="--debug";curl_debug="-v";set -x;;
      "--verbose") verbose="--verbose";;
      "--upgrade") upgrade="--upgrade";;
      "--plan-only") op="--plan-only";;
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

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/lib.sh

export mgmt_cluster_name="$(kubectl get cm -n ${NAMESPACE} cluster-config -o=jsonpath='{.data.mgmtClusterName}')"

if [ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]; then # workflow_dispatch on env repo
  export ENV_BRANCH="${GITHUB_REF_NAME}"
else # Commit on env repo
  if [ "${GITHUB_REF_NAME}" != main ]; then # Pull Request
    export ENV_BRANCH="${GITHUB_HEAD_REF}"
    op="--plan-only"
  else
    op="" # default is to apply on main branch
  fi
fi

export ENV_BRANCH="${ENV_BRANCH:-main}"
export K8S_BRANCH="${K8S_BRANCH:-main}"

get_token updater
export GHT_UPDATE=$token
export GHT_UPDATE_EXPIRY=$token_expiry

set +e
git clone --depth 20 --branch ${ENV_BRANCH} https://git:${GHT_UPDATE}@github.com/${GITHUB_REPOSITORY}.git ${GITHUB_REPOSITORY} >/dev/null
ret="$?"
set -e
if [[ $ret -ne 0 ]]; then
  echo "Environment: $ENVIRONMENT, environment repository does not have a branch named: $ENV_BRANCH, using main"
  ENV_BRANCH=main
  git clone --depth 100 --branch ${ENV_BRANCH} https://git:${GHT_UPDATE}@github.com/${GITHUB_REPOSITORY}.git ${GITHUB_REPOSITORY} >/dev/null
fi
