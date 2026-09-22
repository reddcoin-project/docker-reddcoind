#!/usr/bin/env bash

set -o pipefail

#
## Given a locally built image, this script starts it on mainnet, testnet and regtest, and checks that each node
##   does real work on threads other than the main one.  That is where the 4.22.9.5 image crashed with exit 139
##   before RED-145, when scrypt proof of work checks overflowed musl's default 128 KiB thread stack.
##   - mainnet: syncs headers from peers past 44,000, where proof of work checks begin
##   - testnet: connects the genesis block, and syncs headers from peers
##   - regtest: connects the genesis block, and mines blocks over RPC
##   Every node is started through the image's own setup.sh, and has to shut down cleanly on `docker stop`.
##
## mainnet and testnet connect to the real networks to sync headers, for up to 4 minutes each.
##   Each node's data is removed as soon as its checks finish.
#

# required image
IMAGE=$1
shift

# Verify image to-be-tested is provided
if [[ -z "$IMAGE" ]]; then
  >&2 printf "\nERR: image missing:  image needs to be passed as the first argument, optionally followed by networks.  Try:\n"
  >&2 printf "\tdocker build 4.22/ --build-arg ARCH=amd64 -t reddcoind:local\n"
  >&2 printf "\t./%s  %s\n"     "$(basename "$0")"  "reddcoind:local"
  >&2 printf "\t./%s  %s\n\n"   "$(basename "$0")"  "reddcoind:local  test regtest"
  exit 1
fi

NETWORKS=("$@")
[[ "${#NETWORKS[@]}" -eq 0 ]] && NETWORKS=(main test regtest)
for net in "${NETWORKS[@]}"; do
  if [[ ! "$net" =~ ^(main|test|regtest)$ ]]; then
    >&2 printf "\nERR: unknown network: %s  (use main, test, or regtest)\n\n" "$net"
    exit 1
  fi
done

for cmd in docker jq; do
  if ! command -v "$cmd" >/dev/null; then
    >&2 printf "\nERR: %s is required\n\n" "$cmd"
    exit 1
  fi
done

MAIN_HEADERS=60000   # proof of work headers, and the RED-145 crash, begin at ~44,000
TEST_HEADERS=50000   # every testnet header is newer than the proof of work cutoff
SYNC_LIMIT=240       # seconds allowed to reach the header target
MINE_BLOCKS=20
FAILED=0
NAME=

cleanup() {
  [[ -n "$NAME" ]] || return 0
  docker rm -fv "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=$((FAILED + 1)); }

running()   { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == true ]]; }
exit_code() { docker inspect -f 'exit code {{.State.ExitCode}}' "$NAME"; }
state()     { if running; then echo "$1"; else exit_code; fi; }  # $1 if still running, the exit code if not
last_logs() { docker logs --tail 3 "$NAME" 2>&1 | awk '{print "        | " $0}'; }
cli()       { docker exec "$NAME" reddcoin-cli "$@"; }

# Wait until RPC answers.  Fails if the container dies, or after 120s
wait_rpc() {
  local i=0
  until cli getblockcount >/dev/null 2>&1; do
    running || return 1
    i=$((i + 1))
    [[ "$i" -ge 120 ]] && return 1
    sleep 1
  done
}

# Sync headers from peers until <target> is reached, within SYNC_LIMIT seconds
sync_headers() {
  local target="$1" headers=0 peers=0 start=$SECONDS
  while [[ $((SECONDS - start)) -lt "$SYNC_LIMIT" ]]; do
    if ! running; then
      fail "crashed during header sync ($(exit_code)) at $headers headers, after $((SECONDS - start))s"
      last_logs
      return
    fi
    headers="$(cli getblockchaininfo 2>/dev/null | jq -r '.headers' 2>/dev/null || echo "$headers")"
    peers="$(cli getconnectioncount 2>/dev/null || echo "$peers")"
    if [[ "$headers" -ge "$target" ]]; then
      pass "synced $headers headers in $((SECONDS - start))s from $peers peer(s), past the $target target"
      return
    fi
    sleep 5
  done
  fail "only $headers headers after ${SYNC_LIMIT}s from $peers peer(s), target was $target"
}

# Mine blocks over RPC, which checks their proof of work on RPC worker threads
mine_blocks() {
  local addr mined
  cli createwallet test-networks >/dev/null 2>&1
  addr="$(cli getnewaddress 2>&1)"
  mined="$(cli generatetoaddress "$MINE_BLOCKS" "$addr" 2>&1 | jq -r 'length' 2>/dev/null)"
  if running && [[ "$mined" == "$MINE_BLOCKS" ]] && [[ "$(cli getblockcount)" == "$MINE_BLOCKS" ]]; then
    pass "mined $MINE_BLOCKS blocks over RPC, height is now $MINE_BLOCKS"
  else
    fail "mining $MINE_BLOCKS blocks: mined '$mined', $(state "height $(cli getblockcount 2>&1)")"
    last_logs
  fi
}

# `docker stop` has to end in a clean shutdown
check_stop() {
  if ! running; then
    fail "node was no longer running before docker stop ($(exit_code))"
    return
  fi
  local start=$SECONDS code
  docker stop -t 60 "$NAME" >/dev/null
  code="$(docker inspect -f '{{.State.ExitCode}}' "$NAME")"
  if [[ "$code" == 0 ]] && docker logs "$NAME" 2>&1 | grep -q 'Shutdown: done'; then
    pass "docker stop shut it down cleanly in $((SECONDS - start))s"
  else
    fail "docker stop: exit code $code, $(docker logs "$NAME" 2>&1 | grep -c 'Shutdown: done') 'Shutdown: done' lines"
  fi
}


for net in "${NETWORKS[@]}"; do
  NAME="reddcoind-nettest-$net"
  cleanup
  printf "\n%s\n" "$net"

  case "$net" in
    main)
      docker run -d --name "$NAME" "$IMAGE" >/dev/null
      ;;
    test)
      docker run -d --name "$NAME" -e TESTNET=1 "$IMAGE" >/dev/null
      ;;
    regtest)
      # setup.sh has no regtest option, so seed a config for it to use as-is
      docker volume create "$NAME" >/dev/null
      docker run --rm -v "$NAME:/home/reddcoind/.reddcoin" --entrypoint sh "$IMAGE" -c \
        "printf 'regtest=1\nserver=1\nlisten=0\ndnsseed=0\n' > /home/reddcoind/.reddcoin/reddcoin.conf"
      docker run -d --name "$NAME" --network none -v "$NAME:/home/reddcoind/.reddcoin" "$IMAGE" >/dev/null
      ;;
  esac

  if ! wait_rpc; then
    fail "node did not start ($(state "RPC not answering after 120s"))"
    last_logs
  else
    pass "started on chain '$(cli getblockchaininfo | jq -r .chain)' with the genesis block connected"
    case "$net" in
      main)    sync_headers "$MAIN_HEADERS" ;;
      test)    sync_headers "$TEST_HEADERS" ;;
      regtest) mine_blocks ;;
    esac
    check_stop
  fi

  cleanup
done


printf "\n"
if [[ "$FAILED" -gt 0 ]]; then
  >&2 printf "ERR: %s check(s) failed\n\n" "$FAILED"
  exit 1
fi
echo "All checks passed"
