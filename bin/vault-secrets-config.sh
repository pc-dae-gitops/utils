#!/usr/bin/env bash

# Utility for configuring vault kv secrets engine
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] " >&2
    echo "This script will configure vault" >&2
}

function args() {

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  tls_skip=""
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--tls-skip") tls_skip="-tls-skip-verify";;
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

source $(local_or_global resources/github-config.sh)
source resources/github-secrets.sh

export VAULT_ADDR="https://vault.${local_dns}"
export VAULT_TOKEN="$(jq -r '.root_token' resources/.vault-init.json)"
export DEX_URL="https://dex.${local_dns}"

set +e

vault policy write $tls_skip admin - << EOF
path "*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}
EOF

vault secrets enable $tls_skip  -path=secrets kv-v2
vault secrets enable $tls_skip  -path=leaf-cluster-secrets kv-v2
