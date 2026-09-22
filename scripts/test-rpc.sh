#!/usr/bin/env bash

set -eo pipefail

#
## Given a locally built image, this script checks how its RPC interface is secured:
##   1. no RPC_* variables: RPC only listens inside the container, and uses cookie auth
##   2. RPC_USERNAME and RPC_PASSWORD must be set together
##   3. all RPC_* variables: remote access works with the password, and the password stays out of `docker logs`
##   4. connections from outside RPC_ALLOW_IP are refused
##   5. a config with the old insecure image defaults triggers a warning at startup
##   6. the README compose setup: the host reaches RPC through a port published on 127.0.0.1
##
## Nothing connects to the Reddcoin network or syncs: checks run with --network none or an --internal
##   Docker network, and check 6 disables peer connections in its config.  Everything created is removed on exit.
#

# required image
IMAGE=$1

# Verify image to-be-tested is provided
if [[ -z "$IMAGE" ]]; then
  >&2 printf "\nERR: image missing:  image needs to be passed as the first argument.  Try:\n"
  >&2 printf "\tdocker build 4.22/ --build-arg ARCH=amd64 -t reddcoind:local\n"
  >&2 printf "\t./%s  %s\n\n"   "$(basename "$0")"  "reddcoind:local"
  exit 1
fi

for cmd in docker curl; do
  if ! command -v "$cmd" >/dev/null; then
    >&2 printf "\nERR: %s is required\n\n" "$cmd"
    exit 1
  fi
done

NAME=reddcoind-rpctest
CONF=/home/reddcoind/.reddcoin/reddcoin.conf
PASSWORD="test-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
HOST_PORT=28443
FAILED=0

cleanup() {
  docker rm -fv "$NAME" >/dev/null 2>&1 || true
  docker network rm "$NAME-int" "$NAME-other" >/dev/null 2>&1 || true
  docker volume rm "$NAME-old" "$NAME-host" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

pass() { printf "  PASS  %s\n" "$1"; }
fail() {
  printf "  FAIL  %s\n" "$1"
  printf "        got: %s\n" "$(head -c 300 <<<"$2" | tr '\n' ' ')"
  FAILED=$((FAILED + 1))
}

# expect <description> <text> <regex>:  passes when the regex matches somewhere in the text
expect() { if grep -qE -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "$2"; fi; }

# expect_no <description> <text> <regex>:  passes when the regex matches nowhere in the text
expect_no() { if grep -qE -- "$3" <<<"$2"; then fail "$1" "$2"; else pass "$1"; fi; }

# Wait until reddcoin-cli inside the container answers, i.e. the daemon has fully started
wait_ready() {
  local i=0
  until docker exec "$NAME" reddcoin-cli getblockcount >/dev/null 2>&1; do
    i=$((i + 1))
    if [[ "$i" -ge 120 ]] || [[ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ]]; then
      >&2 printf "\nERR: reddcoind did not start (%s).  Last log lines:\n\n" \
        "$(docker inspect -f '{{if .State.Running}}still not answering after 120s{{else}}container exited with code {{.State.ExitCode}}{{end}}' "$NAME")"
      >&2 docker logs --tail 20 "$NAME"
      exit 1
    fi
    sleep 1
  done
}

# Seed a data volume with a reddcoin.conf, so setup.sh uses it instead of generating one
seed_config() {
  docker volume create "$1" >/dev/null
  docker run --rm -v "$1:/home/reddcoind/.reddcoin" --entrypoint sh "$IMAGE" -c "printf '$2' > $CONF"
}

# Run reddcoin-cli from a separate container against the node:  remote_cli <network> <node ip> <password>
remote_cli() {
  docker run --rm --network "$1" --entrypoint reddcoin-cli "$IMAGE" \
    -rpcconnect="$2" -rpcport=45443 -rpcuser=alice -rpcpassword="$3" -rpcclienttimeout=30 getblockcount 2>&1 | head -n 1
}

rpc_listen() { docker exec "$NAME" netstat -tln | awk '$4 ~ /:45443$/ {print $4}'; }


printf "\n1. No RPC_* variables\n"
docker run -d --name "$NAME" --network none "$IMAGE" >/dev/null
wait_ready
conf="$(docker exec "$NAME" cat "$CONF")"
listen="$(rpc_listen)"
expect_no "config has no rpcuser, rpcpassword, rpcallowip or rpcbind" "$conf" '^rpc(user|password|allowip|bind)='
expect    "RPC listens on 127.0.0.1" "$listen" '^127\.0\.0\.1:45443$'
expect_no "RPC listens on nothing but loopback" "$(grep -vE '^(127\.0\.0\.1|::1):' <<<"$listen" || true)" '.'
expect    "reddcoin-cli works with cookie auth" "$(docker exec "$NAME" reddcoin-cli getblockcount 2>&1)" '^[0-9]+$'
expect_no "no insecure RPC warning" "$(docker logs "$NAME" 2>&1)" 'WARNING: insecure RPC'
docker rm -fv "$NAME" >/dev/null


printf "\n2. Only one of RPC_USERNAME / RPC_PASSWORD\n"
for var in RPC_USERNAME=alice "RPC_PASSWORD=$PASSWORD"; do
  docker run -d --name "$NAME" --network none -e "$var" "$IMAGE" >/dev/null
  # an image that accepts the setting keeps running, so don't wait on it forever
  rc="$(timeout 30 docker wait "$NAME" 2>/dev/null || echo "still running after 30s")"
  out="$(docker logs "$NAME" 2>&1 | tail -n 3)"
  expect "only ${var%%=*} set: refuses to start" "exit=$rc $out" '^exit=[1-9].*ERR: set both RPC_USERNAME and RPC_PASSWORD'
  docker rm -fv "$NAME" >/dev/null
done


printf "\n3. All RPC_* variables, client on an internal Docker network\n"
docker network create --internal "$NAME-int" >/dev/null
docker run -d --name "$NAME" --network "$NAME-int" \
  -e RPC_USERNAME=alice -e "RPC_PASSWORD=$PASSWORD" -e RPC_BIND=0.0.0.0 -e RPC_ALLOW_IP=172.16.0.0/12 \
  "$IMAGE" >/dev/null
wait_ready
ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NAME-int\").IPAddress}}" "$NAME")"
expect    "network is inside 172.16.0.0/12" "$ip" '^172\.(1[6-9]|2[0-9]|3[01])\.'
expect    "RPC listens on 0.0.0.0" "$(rpc_listen)" '^0\.0\.0\.0:45443$'
expect    "remote client with the password gets an answer" "$(remote_cli "$NAME-int" "$ip" "$PASSWORD")" '^[0-9]+$'
expect    "remote client with a wrong password is rejected" "$(remote_cli "$NAME-int" "$ip" wrong)" 'Incorrect rpcuser or rpcpassword'
expect    "password never appears in docker logs" "$(docker logs "$NAME" 2>&1 | grep -cF -- "$PASSWORD" || true) times" '^0 times$'
expect_no "no insecure RPC warning" "$(docker logs "$NAME" 2>&1)" 'WARNING: insecure RPC'


printf "\n4. Client outside RPC_ALLOW_IP\n"
docker network create --internal --subnet 10.99.0.0/24 "$NAME-other" >/dev/null
docker network connect "$NAME-other" "$NAME"
ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NAME-other\").IPAddress}}" "$NAME")"
expect    "client from 10.99.0.0/24 is refused, even with the password" "$(remote_cli "$NAME-other" "$ip" "$PASSWORD")" 'HTTP error 403'
docker rm -fv "$NAME" >/dev/null


printf "\n5. Existing config with the old image defaults\n"
seed_config "$NAME-old" 'server=1\nrpcuser=rpcusername\nrpcpassword=rpcpassword\nrpcallowip=0.0.0.0/0\nrpcport=45443\nrpcbind=0.0.0.0\n'
docker run -d --name "$NAME" --network none -v "$NAME-old:/home/reddcoind/.reddcoin" "$IMAGE" >/dev/null
wait_ready
logs="$(docker logs "$NAME" 2>&1)"
expect    "existing config is left alone" "$logs" 'is already existent'
expect    "warns about the default password" "$logs" 'rpcpassword is the old image default'
expect    "warns about rpcallowip=0.0.0.0/0" "$logs" 'rpcallowip ends in /0'
docker rm -fv "$NAME" >/dev/null


printf "\n6. README compose setup: host -> 127.0.0.1:%s, RPC_ALLOW_IP=172.16.0.0/12\n" "$HOST_PORT"
# This one needs a normal Docker network for the published port, so connect=0, dnsseed=0 and listen=0
#   keep the node from making or accepting any peer connections
seed_config "$NAME-host" "server=1\nconnect=0\ndnsseed=0\nlisten=0\nrpcuser=alice\nrpcpassword=$PASSWORD\nrpcallowip=172.16.0.0/12\nrpcport=45443\nrpcbind=0.0.0.0\n"
docker run -d --name "$NAME" -p "127.0.0.1:$HOST_PORT:45443" -v "$NAME-host:/home/reddcoind/.reddcoin" "$IMAGE" >/dev/null
wait_ready
expect    "host gets an answer through the published port" \
  "$(curl -s --max-time 10 -u "alice:$PASSWORD" --data '{"method":"getblockcount"}' "http://127.0.0.1:$HOST_PORT/")" '"result":[0-9]+'
expect    "node has no peer connections" "$(docker exec "$NAME" reddcoin-cli getconnectioncount 2>&1)" '^0$'
expect    "port is only published on the host's loopback" "$(docker port "$NAME" 45443)" '^127\.0\.0\.1:'
expect_no "port is not published on any other address" "$(docker port "$NAME" 45443 | grep -v '^127\.0\.0\.1:' || true)" '.'


printf "\n"
if [[ "$FAILED" -gt 0 ]]; then
  >&2 printf "ERR: %s check(s) failed\n\n" "$FAILED"
  exit 1
fi
echo "All checks passed"
