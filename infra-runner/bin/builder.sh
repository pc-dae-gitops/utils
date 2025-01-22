#!/usr/bin/env bash

# Build an image

set -euo pipefail

function usage()
{
  echo "usage ${0} [--debug] " >&2
  echo "This script runs a build script on the GHA runner pod's docker container" >&2
}

function args() {
  debug=""
  curl_debug="-s"
  op=""
  build_prep=""
  build_script=""

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
      "--debug") debug="--debug";curl_debug="-v";set -x;;
      "--plan-only") op="--plan-only";; # Not used, required because infra.sh supplies it
      "--build-script") (( arg_index+=1 ));build_script=${arg_list[${arg_index}]};;
      "--build-prep") (( arg_index+=1 ));build_prep=${arg_list[${arg_index}]};;
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
  if [ -z "$build_script" ]; then
    echo "--build-script is required"
    usage
    exit 1
  fi
}

function docker() {
  kubectl exec -n $POD_NAMESPACE $POD_NAME -c docker -- /bin/docker.sh $debug $@
}

function docker_exec() {
  kubectl exec -n $POD_NAMESPACE $POD_NAME -c docker -- bash -c "$@"
}

function copy_repo() {
  repo="$(basename $PWD)"
  pushd ..
  mkdir -p /tmp/repos
  cp -rf $repo /tmp/repos
  popd
}

args "$@"

if [ -n "$build_prep" ]; then
  $build_prep $debug
fi
copy_repo

docker_exec "mkdir -p /tmp/repos"
docker_exec "echo \"export RUN_ID=$RUN_ID\" > /tmp/repos/env.sh"

if [ "${RUNNER:-}" == "true" ]; then
  if [ -z "${RUNNER_VERSION:-}" ]; then
    RUNNER_VERSION="$(/home/runner/bin/infractl runners get-actions-release)"
  fi

  if [[ $RUNNER_VERSION =~ ^v ]]; then
    RUNNER_VERSION="${RUNNER_VERSION:1}"
  fi
  docker_exec "echo \"export RUNNER_VERSION=$RUNNER_VERSION\" >> /tmp/repos/env.sh"
fi

kubectl cp /tmp/repos/$repo -n $POD_NAMESPACE $POD_NAME:/tmp/repos -c docker

docker_exec "/tmp/repos/$repo/$build_script $debug --version $VERSION --cache $CACHE"
