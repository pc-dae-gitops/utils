#!/usr/bin/env bash

# Utility to deploy kind cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--install] [--username <username>] [--cluster-name <hostname>]  [--hostname <hostname>] [--listen-address <ip address>] [--listen-port <port>] [--mgmt]" >&2
    echo "This script will deploy Kubernetes cluster on the local machine or another host" >&2
    echo "The target machine must be accessible via ssh using hostname, add the hostname to /etc/hosts if needed first" >&2
    echo "use --mgmt option when creating a mgmt cluster" >&2
}

function args() {
  install=""
  username_str=""
  listen_address="127.0.0.1"
  listen_port="6443"
  hostname="localhost"
  cluster_name="kind"
  debug_str=""
  mgmt=""

  ssh_opts="-o StrictHostKeyChecking=no"
  scp_opts="-o StrictHostKeyChecking=no"
  ssh_cmd="ssh $ssh_opts"
  scp_cmd="scp $scp_opts"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--install") install="true";;
          "--mgmt") mgmt="true";;
          "--cluster-name") (( arg_index+=1 )); cluster_name="${arg_list[${arg_index}]}";;
          "--hostname") (( arg_index+=1 )); hostname="${arg_list[${arg_index}]}";;
          "--username") (( arg_index+=1 )); username_str="${arg_list[${arg_index}]}@";;
          "--listen-address") (( arg_index+=1 )); listen_address="${arg_list[${arg_index}]}";;
          "--listen-port") (( arg_index+=1 )); listen_port="${arg_list[${arg_index}]}";;
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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh
utils_dir="$(realpath $SCRIPT_DIR/..)"
source resources/github-secrets.sh
location="${hostname}" #:-localhost}"

export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

export leaf_target_path="clusters/kind/$location-$cluster_name"
cat .envrc | grep "export GITHUB_" > /tmp/${location}-${cluster_name}-env.sh
echo "export GITHUB_TOKEN_READ=${GITHUB_TOKEN_READ}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export GITHUB_TOKEN_WRITE=${GITHUB_TOKEN_WRITE}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export target_path=${leaf_target_path}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export listen_address=${listen_address}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export listen_port=${listen_port}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export cluster_name=${cluster_name}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export hostname=${hostname}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export KUBECONFIG=/tmp/${cluster_name}.kubeconfig" >> /tmp/${location}-${cluster_name}-env.sh
echo "export PREFIX_NAME=${PREFIX_NAME}" >> /tmp/${location}-${cluster_name}-env.sh

cp -r /tmp/${location}-${cluster_name}-env.sh /tmp/env.sh
cp -r ${utils_dir}/kind-leafs /tmp
cp -r $(local_or_global resources/kind.yaml) /tmp
cp -r $(local_or_global resources/audit.yaml) /tmp

export hostname=localhost
${utils_dir}/kind-leafs/leaf-deploy.sh $debug_str

cp /tmp/${cluster_name}.kubeconfig ~/.kube/config

kubectl label node dell-control-plane ingress-ready="true"

