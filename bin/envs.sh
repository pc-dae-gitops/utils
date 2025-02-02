#!/usr/bin/env bash

# Check user is in subdirectory of their dae GitOps Cluster repository
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@dae.mn)

top_level=$(git rev-parse --show-toplevel)
if [ -f ${top_level}/.envrc ]; then
  pushd ${top_level}
  source .envrc
else
  echo "No .envrc found in ${top_level}"
  exit 1
fi
