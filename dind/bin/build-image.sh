#!/usr/bin/env bash

# Build image

function cleanup() {
  exit_code=$?
  if [[ $(docker buildx ls --format=json | jq -r '.Name' | grep build-dind-image-${RUN_ID:-} | wc -l) -ne 0 ]]; then 
      docker buildx rm build-dind-image-${RUN_ID:-}
  fi
  if [[ -n "${debug:-}" && $exit_code -ne 0 ]]; then
    echo "sleep 300 to allow debugging"
    sleep 300
  fi
}

trap cleanup 0

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] --version <version>" >&2
    echo "This script will build and push an new dind-image image" >&2
}

function args() {
  export VERSION=""
  local_build=""
  cache="none"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") debug="--debug";set -x;;
          "--local") local_build="true";;
          "--version") (( arg_index+=1 ));VERSION=${arg_list[${arg_index}]};;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
              echo "invalid argument: ${arg_list[${arg_index}]}" >&2
              usage; exit 1
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done

  if [ -z "${VERSION}" ]; then
    echo "No version specified" >&2
    usage; exit
  fi
}

args "$@"

if [[ "$OSTYPE" != "darwin"* ]]; then
  cd /tmp/repos/utils
fi

export BASE_DIR=$(git rev-parse --show-toplevel)

if [[ "$OSTYPE" == "darwin"* ]]; then
  RUN_ID=$$
else
  if [ -f "../env.sh" ]; then
    source ../env.sh
  fi
fi

pushd ${BASE_DIR}/dind

if [ -z "$local_build" ]; then
  set +e
  count=5
  while (( 1 == 1 ))
  do
    docker buildx create --bootstrap --name=build-dind-image-$RUN_ID --driver=kubernetes \
      "--driver-opt=namespace=$POD_NAMESPACE,rootless=true,replicas=1,"nodeselector=role=buildx",requests.cpu=3.5,requests.memory=14Gi,limits.cpu=3.5,limits.memory=14Gi"
    if [[ $? -eq 0 ]]; then
      break
    else
      docker buildx rm build-dind-image-$RUN_ID
    fi
    count=`expr $count - 1`
    if [[ $count -eq 0 ]]; then
      echo "failed to start Kubernetes builder"
      exit 1
    fi
  done
  set -e
  docker buildx use build-dind-image-$RUN_ID
fi

docker buildx build --platform linux/amd64 . -f Dockerfile --push -t paulcarltondae/dind:$VERSION 
