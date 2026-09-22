#!/bin/bash
# no `set -x`: it would print RPC_PASSWORD into `docker logs`
set -e
HOME_PATH=/home/reddcoind
CONFIG_PATH=/.reddcoin/reddcoin.conf
BOOTSTRAP=bootstrap.tar.gz
if [ ! -f $HOME_PATH$CONFIG_PATH ]; then
  if [[ -n $RPC_USERNAME && -z $RPC_PASSWORD ]] || [[ -z $RPC_USERNAME && -n $RPC_PASSWORD ]]; then
    echo "ERR: set both RPC_USERNAME and RPC_PASSWORD, or neither to use cookie authentication" >&2
    exit 1
  fi

  echo "Creating $HOME_PATH$CONFIG_PATH"
  echo "server=$RPC_SERVER" >> $HOME_PATH$CONFIG_PATH
  # Without rpcuser/rpcpassword reddcoind uses cookie auth, which `reddcoin-cli` inside the container picks up
  if [ -n "$RPC_PASSWORD" ]; then
    echo "rpcuser=$RPC_USERNAME" >> $HOME_PATH$CONFIG_PATH
    echo "rpcpassword=$RPC_PASSWORD" >> $HOME_PATH$CONFIG_PATH
  fi
  # Without rpcallowip reddcoind only accepts RPC connections from inside the container
  if [ -n "$RPC_ALLOW_IP" ]; then
    echo "rpcallowip=$RPC_ALLOW_IP" >> $HOME_PATH$CONFIG_PATH
  fi
  echo "zmqpubrawblock=$ZMQ_PUBRAWBLOCK" >> $HOME_PATH$CONFIG_PATH
  echo "zmqpubrawtx=$ZMQ_PUBRAWTX" >> $HOME_PATH$CONFIG_PATH
  echo "printtoconsole=$DAEMON_OPTION_PRINTTOCONSOLE" >> $HOME_PATH$CONFIG_PATH
  echo "txindex=$DAEMON_OPTION_TXINDEX" >> $HOME_PATH$CONFIG_PATH
  echo "testnet=$TESTNET" >> $HOME_PATH$CONFIG_PATH
  # rpcport and rpcbind only apply to the network section they're in
  if [[ $TESTNET == 1 ]]; then
    echo "[test]" >> $HOME_PATH$CONFIG_PATH
  fi
  echo "rpcport=$RPC_PORT" >> $HOME_PATH$CONFIG_PATH
  if [ -n "$RPC_BIND" ]; then
    echo "rpcbind=$RPC_BIND" >> $HOME_PATH$CONFIG_PATH
  fi
else
  echo "$HOME_PATH$CONFIG_PATH is already existent..."
fi

# Older versions of this image wrote rpcpassword=rpcpassword and rpcallowip=0.0.0.0/0 by default,
# and setup.sh never rewrites an existing config, so warn about those on every start
RPC_WARNINGS=()
if grep -qE '^[[:space:]]*rpcpassword[[:space:]]*=[[:space:]]*rpcpassword[[:space:]]*$' $HOME_PATH$CONFIG_PATH; then
  RPC_WARNINGS+=("rpcpassword is the old image default \"rpcpassword\"")
fi
if grep -qE '^[[:space:]]*rpcallowip[[:space:]]*=.*/(0|0\.0\.0\.0)[[:space:]]*$' $HOME_PATH$CONFIG_PATH; then
  RPC_WARNINGS+=("rpcallowip ends in /0, which allows RPC connections from any address")
fi
if [ ${#RPC_WARNINGS[@]} -gt 0 ]; then
  {
    echo "WARNING: insecure RPC settings in $HOME_PATH$CONFIG_PATH:"
    printf '  - %s\n' "${RPC_WARNINGS[@]}"
    echo "  Anyone who can reach the RPC port can control this node and its wallet."
    echo "  Set a strong rpcpassword and narrow rpcallowip, or delete the file to regenerate it from the RPC_* environment variables."
  } >&2
fi

if [ -f "$HOME_PATH/bootstrap/"$BOOTSTRAP ]; then
  echo "Found $HOME_PATH/bootstrap/$BOOTSTRAP"
  echo "Which network are we targeting?"
  if [[ $TESTNET == 0 ]]; then
    echo "Pointing to MAINNET"
    if [ -d "$HOME_PATH/.reddcoin/blocks" ]; then
      echo "Skipping Bootstrap file cause of already existent blocks in $HOME_PATH/.reddcoin"
    else
      cd "$HOME_PATH/.reddcoin" && rm -rf blocks chainstate database
      tar -zxvf "$HOME_PATH/bootstrap/$BOOTSTRAP" -C "$HOME_PATH/.reddcoin"
    fi
  elif [[ $TESTNET == 1 ]]; then
    echo "Pointing to TESTNET"
    if [ -d "$HOME_PATH/.reddcoin/testnet3/blocks" ]; then
      echo "Skipping Bootstrap file cause of already existent blocks in $HOME_PATH/.reddcoin/testnet3"
    else
      cd "$HOME_PATH/.reddcoin/testnet3" && rm -rf blocks chainstate database
      tar -zxvf "$HOME_PATH/bootstrap/$BOOTSTRAP" -C "$HOME_PATH/.reddcoin/testnet3"
    fi
  fi
else
  echo "Could not find $HOME_PATH/bootstrap/$BOOTSTRAP"
fi

[ -f "$HOME_PATH/.reddcoin/.lock" ] && rm -f "$HOME_PATH/.reddcoin/.lock"

# exec so reddcoind replaces this shell as PID 1 and receives SIGTERM from `docker stop` for a clean shutdown
exec /usr/local/bin/reddcoind
