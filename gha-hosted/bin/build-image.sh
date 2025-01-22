#!/usr/bin/env bash

# Build image

function cleanup() {
  exit_code=$?
  if [[ $(docker buildx ls --format=json | jq -r '.Name' | grep build-gha-hosted-${RUN_ID:-} | wc -l) -ne 0 ]]; then 
      docker buildx rm build-gha-hosted-${RUN_ID:-}
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
    echo "usage ${0} [--debug] [--local] [--cache <ecr|none>] --version <version>" >&2
    echo "This script will build and push an new runner image" >&2
    echo "Use --local to build on local machine rather than using buildx pod in test-ci-one"
    echo "Use --cache to specify the caching option, defaults to none, other options not supported if --local is used"
}

function args() {
  export VERSION=""
  export RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
  debug=""
  local_build=""
  cache="none"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") debug="--debug";set -x;;
          "--local") local_build="true";;
          "--cache") (( arg_index+=1 ));cache=${arg_list[${arg_index}]};;
          "--version") (( arg_index+=1 ));VERSION=${arg_list[${arg_index}]};;
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
  POD_NAMESPACE=default
  export KUBECONFIG=~/dell.yaml
fi

if [ -f "../env.sh" ]; then
  source ../env.sh
fi

pushd ${BASE_DIR}/gha-hosted

if [ -z "$local_build" ]; then
  set +e
  count=5
  while (( 1 == 1 ))
  do
    docker buildx create --bootstrap --name=build-gha-hosted-$RUN_ID --driver=kubernetes \
      "--driver-opt=namespace=$POD_NAMESPACE,rootless=true,replicas=1,"nodeselector=role=buildx",requests.cpu=3.5,requests.memory=14Gi,limits.cpu=3.5,limits.memory=14Gi"
    if [[ $? -eq 0 ]]; then
      break
    else
      docker buildx rm build-gha-hosted-$RUN_ID
    fi
    count=`expr $count - 1`
    if [[ $count -eq 0 ]]; then
      echo "failed to start Kubernetes builder"
      exit 1
    fi
  done
  set -e
  docker buildx use build-gha-hosted-$RUN_ID
else
  if [ -z "${RUNNER_VERSION:-}" ]; then
    echo "RUNNER_VERSION environmental variable needs to be set to the GitHub actions runner version, without leading"
    exit 1 
  fi
fi

docker buildx build --platform linux/amd64 . -f Dockerfile \
             --push -t paulcarltondae/gha-hosted:$VERSION \
             --label "actions-runner-version=v${RUNNER_VERSION:-}"
