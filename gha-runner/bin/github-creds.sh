#!/usr/bin/env bash

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--type <${type}|updater>]" >&2
    echo "This script gets github creds" >&2
    echo "  --debug: enable debug output" >&2
    echo "  --type: ${type} or updater token, defaults to ${type}" >&2
}

function args() {
  debug=""
  type="${type}"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") debug="--debug";set -x;;
          "--type") (( arg_index+=1 ));type=${arg_list[${arg_index}]};;
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

if [ -n "$debug" ]; then
    echo "environmental variables..."
    env | sort
    echo "Current directory: $(pwd)"
fi

export ${type}_app_install_id="$(kubectl get secret -n ${POD_NAMESPACE} github-${type}-auth -o=jsonpath='{.data.github_app_installation_id}' | base64 -d)"
export ${type}_app_client_id="$(kubectl get secret -n ${POD_NAMESPACE} github-${type}-auth -o=jsonpath='{.data.github_app_client_id}' | base64 -d)"
kubectl get secret -n ${POD_NAMESPACE} github-${type}-auth -o=jsonpath='{.data.github_app_private_key}' | base64 -d | awk '{gsub(/\\n/,"\n")}1' > /tmp/${type}-key.pem
JWT=$(/home/runner/bin/app-jwt.py /tmp/${type}-key.pem $${type}_app_client_id | cut -f2 -d: | sed s/\ //g)
curl -s --request POST --url "https://api.github.com/app/installations/$${type}_app_install_id/access_tokens" \
     --header "Accept: application/vnd.github+json" --header "Authorization: Bearer $JWT" --header "X-GitHub-Api-Version: 2022-11-28" > /tmp/${type}-token.json
export GHT="$(jq -r '.token' /tmp/${type}-token.json)"
export GHT_EXPIRY="$(jq -r '.expires_at' /tmp/${type}-token.json)"
echo "GITHUB_TOKEN=$GHT" >> "$GITHUB_ENV"
# echo "POD_NAMESPACE=$POD_NAMESPACE" >> "$GITHUB_ENV"
