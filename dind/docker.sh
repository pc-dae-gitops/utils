#!/usr/bin/env bash

# Capture modified and deleted files

set -euo pipefail

function usage()
{
  echo "usage ${0} [--debug] <docker command and args> " >&2
  echo "This script executes docker" >&2
}

function args() {
  debug=""

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
      "--debug") debug="--debug";curl_debug="-v";set -x;;
            "-h") usage; exit;;
        "--help") usage; exit;;
            "-?") usage; exit;;
    *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
          echo "invalid argument: ${arg_list[${arg_index}]}" >&2
          usage; exit
        fi;
        docker_args="${arg_list[@]:${arg_index}}"
        if [ -n "$debug" ]; then
          echo "docker args: $docker_args"
        fi
        break;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

docker $docker_args
