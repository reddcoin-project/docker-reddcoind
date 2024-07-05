#!/usr/bin/env bash

set -eo pipefail

#
## This script returns all lnd tags sorted newest to oldest, with all variants of the same version on the same line
#

main() {
  declare repo="$1"

  curl -s "https://hub.docker.com/v2/repositories/$repo/tags" \
    | jq -r '.results|.[]|.name' \
    | grep '^v.*' \
    | grep -v '\-build' \
    | tr -s '-' '~' \
    | sort -Vr | uniq \
    | tr -s '~' '-' \
    | grep -v '\-\(arm32\|arm64\|amd64\|linux-arm\)' \
    | awk -F- 'NR==1 {printf "* "}; $1!=a && NR>1 {print "\n* "}; {ORS=""; printf "`%s` ", $0}; {a=$1}'

    echo
}

main "reddcoincore/reddcoind"
