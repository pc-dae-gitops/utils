#!/usr/bin/env bash

# Capture modified and deleted files

set -euo pipefail

source /home/runner/bin/trap.sh

function usage()
{
    echo "usage ${0} [--debug] [--action <script to execute>]" >&2
    echo "This script syncs the workflow commit and calls the action.sh script by default" >&2
}

function args() {
  debug=""
  verbose=""
  op=""
  unprocessed_args=""
  action="action.sh"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--verbose") verbose="--verbose";;
          "--debug") debug="--debug";set -x;;
          "--action") (( arg_index+=1 ));action=${arg_list[${arg_index}]};;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) echo "skipping argument: ${arg_list[${arg_index}]}" >&2
           unprocessed_args="$unprocessed_args ${arg_list[${arg_index}]}"
           (( arg_index+=1 ))
           continue;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

if [ -n "$debug" ]; then
    echo "environmental variables..."
    env | sort
    echo "Current directory: $(pwd)"
fi

export NAMESPACE="runner-$(echo ${GITHUB_REPOSITORY} | sed s#/#-#g)"

get_token reader
export GHT=$token
export GHT_EXPIRY=$token_expiry

if [ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]; then # workflow_dispatch
  export K8S_BRANCH="${GITHUB_REF_NAME}" # The branch selected to run workflow
else # commit
  if [ "${GITHUB_REF_NAME}" != main ]; then # Pull Request
    export K8S_BRANCH="${GITHUB_HEAD_REF}"
  else # merge request commit
    export K8S_BRANCH="main"
  fi
fi

if [ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]; then # workflow_dispatch
  [ "${APPLY:-false}" == "true" ] && plan="" || plan="--plan-only"
fi

set +e
git clone --depth 1 --branch ${K8S_BRANCH} https://git:${GHT}@github.com/pc-dae-gitops/utils.git >/dev/null
ret="$?"
set -e
if [[ $ret -ne 0 ]]; then
  echo "utils repository does not have a branch named: $K8S_BRANCH, using main"
  K8S_BRANCH=main
  git clone --depth 1 --branch ${K8S_BRANCH} https://git:${GHT}@github.com/pc-dae-gitops/utils.git >/dev/null
fi

export WORK_DIR=$PWD
echo "path: $PATH"
# /home/runner/bin/infractl --version
pushd utils
source infra-runner/bin/trap.sh

unprocessed_args="$unprocessed_args $debug $verbose ${plan:-}"
echo "args being passed on to called script"
echo "$unprocessed_args"

infra-runner/bin/$action $unprocessed_args

popd
