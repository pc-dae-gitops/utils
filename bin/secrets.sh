#!/usr/bin/env bash

# Utility for creating secrets in Vault
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--tls-skip] --secrets <secrets file>" >&2
    echo "This script will create secrets in Vault" >&2
    echo " The --secrets option should reference a bash script which sets the github secrets" >&2
    echo " The --aws-dir option allows the location for the AWS config directory to be specified; default is ~/.aws" >&2
    echo " The --aws-credentials option allows the location for the AWS credentials file to be specified; the defaults is ~/.aws/credentials" >&2
    echo "use the --tls-skip option to load data prior to ingress certificate setup" >&2
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
          "--aws-dir") (( arg_index+=1 ));aws_dir=${arg_list[${arg_index}]};;
          "--aws-credentials") (( arg_index+=1 ));aws_credentials=${arg_list[${arg_index}]};;
          "--secrets") (( arg_index+=1 ));secrets_file=${arg_list[${arg_index}]};;
          "--debug") set -x; debug_str="--debug";;
          "--tls-skip") tls_skip="-tls-skip-verify"; script_tls_skip="--tls-skip";;
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

if [ "$aws" == "true" ]; then
  aws-secrets.sh $debug_str $script_tls_skip --aws-dir ${aws_dir} --aws-credentials ${aws_credentials}
fi
if [ "${azure:-}" == "true" ]; then
  azure-secrets.sh $debug_str
fi

# this is the token for the vault admin user, create a more restricted token for use in default namespace
vault kv put ${tls_skip} -mount=secrets test-one-vault-token vault_token=${VAULT_TOKEN}
vault kv put ${tls_skip} -mount=secrets test-two-vault-token vault_token=${VAULT_TOKEN}
vault kv put ${tls_skip} -mount=secrets kind-vault-token vault_token=${VAULT_TOKEN}
vault kv put ${tls_skip} -mount=secrets flux-apps-vault-token vault_token=${VAULT_TOKEN}

source ${secrets_file}
source $(local_or_global resources/github-config.sh)

vault kv put ${tls_skip} -mount=secrets dex-config config.yaml="$(cat `local_or_global resources/github-dex-config.yaml` | envsubst)"
# vault kv put ${tls_skip} -mount=secrets git-provider-credentials GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID} GITLAB_CLIENT_SECRET=${GITLAB_CLIENT_SECRET} \
#       GITLAB_HOSTNAME=${GITLAB_HOSTNAME} GIT_HOST_TYPE=${GIT_HOST_TYPE}

vault kv put ${tls_skip} -mount=secrets vault-oidc-auth clientID=vault clientSecret=${VAULT_DEX_CLIENT_SECRET}

vault kv put ${tls_skip} -mount=secrets github-repo-read-credentials username=token password=${GITHUB_TOKEN_READ}

vault kv put ${tls_skip} -mount=secrets github-repo-write-credentials username=token password=${GITHUB_TOKEN_WRITE}

vault kv put ${tls_skip} -mount=secrets github-repo-write-token token=${GITHUB_TOKEN_WRITE}

vault kv put ${tls_skip} -mount=secrets github-leaf-token github_token=${GITHUB_TOKEN_WRITE}

RECEIVER_TOKEN=$(head -c 12 /dev/urandom | shasum | cut -d ' ' -f1)
vault kv put ${tls_skip} -mount=secrets receiver-token token=${RECEIVER_TOKEN}

MONITORING_PASSWORD="$(date +%s | sha256sum | base64 | head -c 10)"
vault kv put ${tls_skip} -mount=secrets monitoring-auth auth=$(htpasswd -nb prometheus-user ${MONITORING_PASSWORD})
vault kv put ${tls_skip} -mount=secrets monitoring-basic-auth-password password=${MONITORING_PASSWORD}

echo "Monitoring password is: ${MONITORING_PASSWORD}" | tee $PWD/resources/prometheus-password.txt

HARBOR_PASSWORD="$(date +%s | sha256sum | base64 | head -c 10)"
vault kv put ${tls_skip} -mount=secrets harbor-admin-password adminPasswd=${HARBOR_PASSWORD}

echo "Harbor password is: ${HARBOR_PASSWORD}" | tee $PWD/resources/harbor-password.txt
