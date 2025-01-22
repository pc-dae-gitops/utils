function cleanup() {
  if [ -n "$debug" ]; then
    echo "sleep 300 to allow debugging"
    sleep 300
  fi
  if [ -e /tmp/ks.yaml ]; then
    kubectl delete -f /tmp/ks.yaml
    rm /tmp/ks.yaml
  fi
}

trap cleanup 0

function get_token()
{
  rm -rf $HOME/.kube/config
  token_type=${1}
  app_install_id="$(kubectl get secret -n ${NAMESPACE} github-${token_type}-auth -o=jsonpath='{.data.github_app_installation_id}' | base64 -d)"
  app_client_id="$(kubectl get secret -n ${NAMESPACE} github-${token_type}-auth -o=jsonpath='{.data.github_app_client_id}' | base64 -d)"
  kubectl get secret -n ${NAMESPACE} github-${token_type}-auth -o=jsonpath='{.data.github_app_private_key}' | base64 -d | awk '{gsub(/\\n/,"\n")}1' > /tmp/${token_type}-key.pem
  JWT=$(/home/runner/bin/app-jwt.py /tmp/${token_type}-key.pem $app_client_id | cut -f2 -d: | sed s/\ //g)
  curl -s --request POST --url "https://api.github.com/app/installations/$app_install_id/access_tokens" \
      --header "Accept: application/vnd.github+json" --header "Authorization: Bearer $JWT" --header "X-GitHub-Api-Version: 2022-11-28" > /tmp/${token_type}-token.json
    
  token="$(jq -r '.token' /tmp/${token_type}-token.json)"
  token_expiry="$(jq -r '.expires_at' /tmp/${token_type}-token.json)"
}
