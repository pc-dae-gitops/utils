#!/usr/bin/env bash

# Utility setting local kubernetes cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--flux-bootstrap] [--flux-reset] [--no-wait] [--install]" >&2
    echo "This script will initialize docker kubernetes" >&2
    echo "  --debug: emmit debugging information" >&2
    echo "  --flux-bootstrap: force flux bootstrap" >&2
    echo "  --flux-reset: unistall flux before reinstall" >&2
    echo "  --no-wait: do not wait for flux to be ready" >&2
    echo "  --install: install software required by kind cluster deployment" >&2
}

function args()
{
  wait=1
  install=""
  bootstrap=0
  reset=0
  debug_str=""
  cluster_type=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x; debug_str="--debug";;
          "--no-wait") wait=0;;
          "--install") install="--install";;
          "--flux-bootstrap") bootstrap=1;;
          "--flux-reset") reset=1;;
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
  
  if [ "$aws" == "true" ]; then
    if [ -z "$AWS_PROFILE" ]; then
      echo "AWS_PROFILE not set" >&2
      exit 1
    fi
  fi
}

args "$@"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

if [ -n "$debug_str" ]; then
  env | sort
fi

if [[ "$OSTYPE" == "linux"* ]]; then
  flux_suffix="-mac"
  b64w="-w 0"
else
  flux_suffix="-mac"
  b64w=""
fi

export LOCAL_DNS="$local_dns"
cat $(local_or_global resources/flux${flux_suffix}.yaml) | envsubst > $target_path/flux/flux.yaml
git add $target_path/flux/flux.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "Add flux.yaml"
  git pull
  git push
fi 

echo "Waiting for cluster to be ready"
kubectl wait --for=condition=Available  -n kube-system deployment coredns

git config pull.rebase true

# Install Flux if not present or force reinstall option set

if [[ $bootstrap -eq 0 ]]; then
  set +e
  kubectl get ns | grep flux-system
  bootstrap=$?
  set -e
fi

if [[ $bootstrap -eq 0 ]]; then
  echo "flux-system namespace already. skipping bootstrap"
else
  if [[ $reset -eq 1 ]]; then
    echo "uninstalling flux"
    flux uninstall --silent --keep-namespace
    if [ -e $target_path/flux/flux-system ]; then
      rm -rf $target_path/flux/flux-system
      git add $target_path/flux/flux-system
      if [[ `git status --porcelain` ]]; then
        git commit -m "remove flux-system from cluster repo"
        git pull
        git push
      fi
    fi
  fi

  # If COMPANY_CA_CERT environmental variable is set, create a secret containing company root CA
  if [ -n "${ADD_COMPANY_CA_CERTS:-}" ]; then
    mkdir -p $target_path/flux
    cp $(local_or_global resources/company-ca-cert.yaml)  /tmp/certs.yaml 
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain | sed 's/^/    /' >> /tmp/certs.yaml
    cat resources/ca-cert.pem | sed 's/^/    /' >> /tmp/certs.yaml
    cp /tmp/certs.yaml  $target_path/flux/company-ca-certs.yaml
    git add $target_path/flux/company-ca-certs.yaml
    export COMPANY_CA_CERTS_PATH="company-ca-certs"
    kubectl apply -f $target_path/flux/company-ca-certs.yaml
  else
    export COMPANY_CA_CERTS_PATH="gotk"
  fi

  kustomize build ${config_dir}/mgmt-cluster/addons/flux/$COMPANY_CA_CERTS_PATH | kubectl apply -f-
  source resources/github-secrets.sh

  # Create a secret for flux to use to access the git repo backing the cluster, using write token - write access needed by image automation

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
data:
  username: $(echo -n "git" | base64 ${b64w})
  password: $(echo -n "$GITHUB_TOKEN_WRITE" | base64 ${b64w})
EOF

  # Create flux-system GitRepository and Kustomization

  # git pull
  mkdir -p $target_path/flux/flux-system
  cat $(local_or_global resources/gotk-sync.yaml) | envsubst > $target_path/flux/flux-system/gotk-sync.yaml
  git add $target_path/flux/flux-system/gotk-sync.yaml
  if [[ `git status --porcelain` ]]; then
    git commit -m "update flux-system gotk-sync.yaml"
    git pull
    git push
  fi

  kubectl apply -f $target_path/flux/flux-system/gotk-sync.yaml
fi

# Create a CA Certificate for the ingress controller to use

if [ -f resources/CA.cer ]; then
  echo "Certificate Authority already exists"
else
  ca-cert.sh $debug_str
  git add resources/CA.cer
  if [[ `git status --porcelain` ]]; then
    git commit -m "add CA certificate"
    git pull
    git push
  fi
fi

# Install CA Certificate secret so Cert Manager can issue certificates using our CA

kubectl apply -f ${config_dir}/mgmt-cluster/addons/cert-manager/namespace.yaml
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
data:
  tls.crt: $(base64 ${b64w} -i resources/CA.cer)
  tls.key: $(base64 ${b64w} -i resources/CA.key)
EOF

# Add CA Certificates to namespaces where it is required

namespace_list=$(local_or_global resources/local-ca-namespaces.txt)
export CA_CERT="$(cat resources/CA.cer)"
for nameSpace in $(cat $namespace_list); do
  export nameSpace
  cat $(local_or_global resources/local-ca-ns.yaml) |envsubst | kubectl apply -f -
  kubectl create configmap local-ca -n ${nameSpace} --from-file=resources/CA.cer --dry-run=client -o yaml >/tmp/ca.yaml
  kubectl apply -f /tmp/ca.yaml
done

if [ "$wait" == "1" ]; then
  echo "Waiting for flux to flux-system Kustomization to be ready"
  sleep 3
  flux reconcile kustomization flux-system
  flux reconcile kustomization flux-components
  kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system flux-system
fi

if [ "$wait" == "1" ]; then
  # Wait for ingress controller to start
  echo "Waiting for ingress controller to start"
  kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system nginx
  sleep 5
fi
export CLUSTER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

if [ "$aws" == "true" ]; then
  cp $(local_or_global resources/aws/flux/)* mgmt-cluster/flux/aws
  mkdir -p mgmt-cluster/templates/aws
  cp $(local_or_global resources/aws/templates/)* mgmt-cluster/templates/aws
  git add mgmt-cluster/flux
  git add mgmt-cluster/templates/aws
else
  rm -rf mgmt-cluster/flux/aws-flux.yaml
  rm -rf mgmt-cluster/templates/aws
fi

if [ "$capi" == "true" ]; then
  [ -d mgmt-cluster/flux ] || mkdir -p mgmt-cluster/flux
  [ -d mgmt-cluster/config ] || mkdir -p mgmt-cluster/config
  cp $(local_or_global resources/capi/operator/)* mgmt-cluster/flux/
  cp $(local_or_global resources/capi/flux/)* mgmt-cluster/flux/
  cp $(local_or_global resources/capi/namespace/)* mgmt-cluster/namespace/
  git add mgmt-cluster/flux
fi

export namespace=flux-system
cat $(local_or_global resources/cluster-config.yaml) | envsubst > mgmt-cluster/config/cluster-config.yaml
git add mgmt-cluster/config/cluster-config.yaml

export namespace=\$\{nameSpace\}
cat $(local_or_global resources/cluster-config.yaml) | envsubst > mgmt-cluster/namespace/cluster-config.yaml
git add mgmt-cluster/namespace/cluster-config.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "update cluster config"
  git pull
  git push
fi

# Ensure that the git source is updated after pushing to the remote
flux reconcile source git -n flux-system flux-system

# cat $(local_or_global resources/harbor-values.yaml) | envsubst > resources/harbor.yaml
# helm install harbor harbor/harbor --create-namespace --set-file resources/harbor.yaml

# Wait for vault to start
while ( true ); do
  echo "Waiting for vault to start"
  set +e
  started="$(kubectl get pod/vault-0 -n vault -o json 2>/dev/null | jq -r '.status.containerStatuses[0].started')"
  set -e
  if [ "$started" == "true" ]; then
    break
  fi
  sleep 5
done

sleep 5
# Initialize vault
vault-init.sh $debug_str --tls-skip
vault-unseal.sh $debug_str --tls-skip

export VAULT_TOKEN="$(jq -r '.root_token' resources/.vault-init.json)"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: vault
data:
  vault_token: $(echo -n "$VAULT_TOKEN" | base64 ${b64w})
EOF

set +e
vault-secrets-config.sh $debug_str --tls-skip
set -e

if [ "$aws_capi" == "true" ]; then
  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
fi

if [[ "$OSTYPE" == "darwin"*  && ! -e ~/.aws/credentials ]]; then
  if [ -d ~/Library/Caches/gsts ]; then
    aws_credentials=~/Library/Caches/gsts/credentials
  else
    aws_credentials=~/.aws/credentials
  fi
else
  if [ -d ~/.cache/gsts ]; then
    aws_credentials=~/.cache/gsts/credentials
  else
    aws_credentials=~/.aws/credentials
  fi
fi

secrets.sh $debug_str --tls-skip --secrets $PWD/resources/github-secrets.sh --aws-credentials $aws_credentials

if [ "$aws_capi" == "true" ]; then
  clusterawsadm bootstrap iam create-cloudformation-stack --config $(local_or_global resources/clusterawsadm.yaml) --region $AWS_REGION
  cp $(local_or_global resources/capi/providers/aws/)* mgmt-cluster/flux/
  git add mgmt-cluster/flux/capa.yaml

  if [[ `git status --porcelain` ]]; then
    git commit -m "Add capa"
    git pull
    git push
  fi

  export EXP_EKS=true
  export EXP_MACHINE_POOL=true
  export CAPA_EKS_IAM=true
  export EXP_CLUSTER_RESOURCE_SET=true

  clusterctl init --infrastructure aws
else
  if [ -f mgmt-cluster/flux/capa.yaml ]; then
    rm -rf mgmt-cluster/flux/capa.yaml
    git add mgmt-cluster/flux/capa.yaml
    if [[ `git status --porcelain` ]]; then
      git commit -m "remove capa"
      git pull
      git push
    fi
  fi
fi

if [ "${azure_capi:-}" == "true" ]; then
  cp $(local_or_global resources/capi/providers/azure/)* mgmt-cluster/flux/
  git add mgmt-cluster/flux/capz.yaml

  if [[ `git status --porcelain` ]]; then
    git commit -m "Add capz"
    git pull
    git push
  fi

  if [ ! -f resources/azure-secrets.sh ]; then
    echo "Azure secrets file not found"
    exit 1
  fi

  source resources/azure-secrets.sh

  export AZURE_SUBSCRIPTION_ID="$subscription_id"
  export AZURE_TENANT_ID="$tenant_id"
  export AZURE_CLIENT_ID="$client_id"
  export AZURE_CLIENT_SECRET="$client_secret"


  # Base64 encode the variables
  export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
  export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
  export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
  export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

  # Settings needed for AzureClusterIdentity used by the AzureCluster
  export AZURE_CLUSTER_IDENTITY_SECRET_NAME="cluster-identity-secret"
  export CLUSTER_IDENTITY_NAME="cluster-identity"
  export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"

  # Create a secret to include the password of the Service Principal identity created in Azure
  # This secret will be referenced by the AzureClusterIdentity used by the AzureCluster
  set +e
  kubectl create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}" --namespace "${AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE}"
  set -e

  # Finally, initialize the management cluster
  clusterctl init --infrastructure azure
else
  if [ -f mgmt-cluster/flux/capz.yaml ]; then
    rm -rf mgmt-cluster/flux/capz.yaml
    git add mgmt-cluster/flux/capz.yaml
    if [[ `git status --porcelain` ]]; then
      git commit -m "remove capz"
      git pull
      git push
    fi
  fi
fi

kubectl rollout restart deployment -n external-secrets external-secrets

# Wait for dex to start:
kubectl wait --timeout=5m --for=condition=Ready kustomization/dex -n flux-system

# set +e
# vault-oidc-config.sh $debug_str
# set -e

if [ "${aws:-}" == "true" ]; then
  if [ "$wait" == "1" ]; then
    echo "Waiting for aws to be applied"
    kubectl wait --timeout=5m --for=condition=Ready kustomization/aws -n flux-system
  fi
  ${config_dir}/terraform/bin/tf-apply.sh $debug_str aws-key-pair
fi

if [ "${ecr_repos:-}" == "true" ]; then
  cp $(local_or_global resources/ecr/flux.yaml) mgmt-cluster/flux/ecr.yaml
  git add mgmt-cluster/flux/ecr.yaml

  if [[ `git status --porcelain` ]]; then
    git commit -m "Addresource descriptions and ci"
    git pull
    git push
  fi
fi

add=""
if [ -n "${HARBOR_DNS:-}" ]; then
  cat $(local_or_global resources/harbor-ks.yaml) | envsubst > mgmt-cluster/flux/harbor.yaml
  add=true
else
  if [ -e mgmt-cluster/flux/harbor.yaml ]; then
    rm -rf mgmt-cluster/flux/harbor.yaml
    add=true
  fi
fi

if [ -n "$add" ]; then
  git add mgmt-cluster/flux/harbor.yaml
  if [[ `git status --porcelain` ]]; then
    git commit -m "update harbor config"
    git pull
    git push
    flux reconcile source git flux-system
  fi
fi

add=""
gha_repo_list=resources/gha-repos.txt
if [ -e "$gha_repo_list" ]; then
  add=true
  mkdir -p mgmt-cluster/flux/gha
  cp $(local_or_global resources/gha-controller.yaml)  mgmt-cluster/flux/gha
  gha-secrets.sh --secrets resources/gha-secrets.sh
  for github_org_repo in $(cat $gha_repo_list); do
    export GITHUB_ORG=$(echo $github_org_repo | cut -f1 -d/)
    export GITHUB_REPO=$(echo $github_org_repo | cut -f2 -d/)
    cat $(local_or_global resources/gha-runner.yaml) | envsubst > mgmt-cluster/flux/gha/$GITHUB_ORG-$GITHUB_REPO.yaml
  done
else
  if [ -d mgmt-cluster/flux/gha ]; then
    rm -rf mgmt-cluster/flux/gha
    add=true
  fi
fi

if [ -n "$add" ]; then
  git add mgmt-cluster/flux/gha
  if [[ `git status --porcelain` ]]; then
    git commit -m "update GHA runners config"
    git pull
    git push
    flux reconcile source git flux-system
  fi
fi
