#!/bin/bash
set -ex
HOME_PATH=/home/reddcoind
CONFIG_PATH=/.reddcoin/reddcoin.conf
if [ ! -f $HOME_PATH$CONFIG_PATH ]; then
  echo "server=$RPC_SERVER" >> $HOME_PATH$CONFIG_PATH
  echo "rpcuser=$RPC_USERNAME" >> $HOME_PATH$CONFIG_PATH
  echo "rpcpassword=$RPC_PASSWORD" >> $HOME_PATH$CONFIG_PATH
  echo "rpcallowip=$RPC_ALLOW_IP" >> $HOME_PATH$CONFIG_PATH
  echo "zmqpubrawblock=$ZMQ_PUBRAWBLOCK" >> $HOME_PATH$CONFIG_PATH
  echo "zmqpubrawtx=$ZMQ_PUBRAWTX" >> $HOME_PATH$CONFIG_PATH
  echo "printtoconsole=$DAEMON_OPTION_PRINTTOCONSOLE" >> $HOME_PATH$CONFIG_PATH
  echo "txindex=$DAEMON_OPTION_TXINDEX" >> $HOME_PATH$CONFIG_PATH
  echo "testnet=$TESTNET" >> $HOME_PATH$CONFIG_PATH
  if [[ $TESTNET == 1 ]]; then
    echo "[test]" >> $HOME_PATH$CONFIG_PATH
    echo "rpcport=$RPC_PORT" >> $HOME_PATH$CONFIG_PATH
  else
    echo "rpcport=$RPC_PORT" >> $HOME_PATH$CONFIG_PATH
  fi
else
  echo "$HOME_PATH$CONFIG_PATH is already existent..."
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
      apt-get update && apt-get install -y unzip
      unzip "$HOME_PATH/bootstrap/$BOOTSTRAP" -d "$HOME_PATH/.reddcoin"
    fi
  elif [[ $TESTNET == 1 ]]; then
    echo "Pointing to TESTNET"
    if [ -d "$HOME_PATH/.reddcoin/testnet3/blocks" ]; then
      echo "Skipping Bootstrap file cause of already existent blocks in $HOME_PATH/.reddcoin/testnet3"
    else
      cd "$HOME_PATH/.reddcoin/testnet3" && rm -rf blocks chainstate database
      apt-get update && apt-get install -y unzip
      unzip "$HOME_PATH/bootstrap/$BOOTSTRAP" -d "$HOME_PATH/.reddcoin/testnet3"
    fi
  fi
else
  echo "Could not find $HOME_PATH/bootstrap/$BOOTSTRAP"
fi

[ -f "$HOME_PATH/.reddcoin/.lock" ] && rm -f "$HOME_PATH/.reddcoin/.lock"
/usr/local/bin/reddcoind
