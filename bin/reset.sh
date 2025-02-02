#!/usr/bin/env bash

# Utility resetting local kubernetes cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--delete-tfs]" >&2
    echo "This script will reset docker kubernetes" >&2
}

function args() {
  delete_tfs=0
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--delete-tfs") delete_tfs=1;;
          "--debug") set -x;;
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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

for ns in $(kubectl get ns -o custom-columns=":metadata.name"); do
  for k in $(kubectl get kustomizations.kustomize.toolkit.fluxcd.io -n $ns -o custom-columns=":metadata.name"); do
    flux suspend kustomization -n $ns $k
  done
done

cluster_name=$(kubectl get cm -n flux-system cluster-config -o jsonpath='{.data.mgmtClusterName}')

if [ "$aws" == "true" ]; then
  set +e
  aws s3 ls | grep -E "${PREFIX_NAME}-ac-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state$" > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    aws s3 rm s3://${PREFIX_NAME}-ac-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state/$cluster_name --recursive
    aws s3api delete-bucket --bucket ${PREFIX_NAME}-ac-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state
  fi

  set +e
  aws dynamodb  list-tables | jq -r '.TableNames[]' | grep -E "^${PREFIX_NAME}-ac-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state$" > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    aws dynamodb delete-table --table-name ${PREFIX_NAME}-ac-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state
  fi
fi


rm -rf mgmt-cluster/flux/flux-system
git add -A
if [[ `git status --porcelain` ]]; then
  git commit -m "remove flux resources"
  git pull
  git push
fi

if [[ "$OSTYPE" == "darwin"* ]]; then

  echo "Reset Kubernetes"
  read -p "Press enter to continue" 

  # Wait for kubernetes to be ready
  while ( true ); do
    echo "Waiting for kubernetes to start"
    started="$(docker ps -q --filter 'name=k8s_kube-apiserver')"
    if [ -n "$started" ]; then
      break
    fi
    sleep 1
  done
else
  echo "Deleting Kind cluster and recreating" 
  remove-kind.sh --cluster-name $CLUSTER_NAME
fi
