reddcoincore/reddcoind
=============

[![Build Status]][builds]
[![gh_last_release_svg]][gh_last_release_url]
[![Docker Image Size]][lnd-docker-hub]
[![Docker Pulls Count]][lnd-docker-hub]

[Build Status]: https://github.com/reddcoin-project/docker-reddcoind/workflows/Build%20&%20deploy%20on%20git%20tag%20push/badge.svg
[builds]: https://github.com/reddcoin-project/docker-reddcoind/actions?query=workflow%3A%22Build+%26+deploy+on+git+tag+push%22

[gh_last_release_svg]: https://img.shields.io/github/v/release/reddcoin-project/docker-reddcoind?sort=semver
[gh_last_release_url]: https://github.com/reddcoin-project/docker-reddcoind/releases/latest

[Docker Image Size]: https://img.shields.io/docker/image-size/reddcoincore/reddcoind
[Docker Pulls Count]: https://img.shields.io/docker/pulls/reddcoincore/reddcoind.svg?style=flat
[lnd-docker-hub]: https://hub.docker.com/r/reddcoincore/reddcoind


This repo builds [`reddcoind`] in an [auditable way](https://github.com/reddcoin-project/docker-reddcoind), and packages it into a minimal Docker containers provided for various CPU architectures.

[`reddcoind`]: https://github.com/reddcoin-project/reddcoin


> The work here was initially based on [lncm/docker-bitcoind](https://github.com/lncm/docker-bitcoind) and [ruimarinho/docker-bitcoin-core](https://github.com/ruimarinho/docker-bitcoin-core/), but has significantly diverged since.


#### Details

* **All [`git-tags`]** <small>(and most commits)</small> **are signed** by `ABEDC4489B9188E45C2342A82E91240B293BA5D3`
* **All [`git-tags`]** <small>(and most commits)</small> **are [`opentimestamps`]-ed**
* **All builds aim to be maximally auditable.**  After `git tag push`, the entire process is automated, with each step printed, and the code aiming to be easy to follow
* All builds are based on [Alpine]
* Cross-compiled builds are done using our (also auditable) [`qemu`]
* To fit build and complete `make check` test suite, BerkeleyDB is build separately [here]
* Each build produces binaries for: `amd64`, `arm64v8`, and `arm32v7`
* All architectures are aggregated under an easy-to-use [Docker Manifest]
* All [`git-tags`] are [build automatically], and with an [auditable trace]
* Each successful build of a `git tag` pushes result Docker image to [Docker Hub]
* Images pushed to Docker Hub are never deleted (even if `lnd` version gets overridden, previous one is preserved)
* All `final` images are based on Alpine for minimum base size
* All binaries are [`strip`ped]
* Each `git-tag` build is tagged with a unique tag number
* Each _minor_ version is stored in a separate directory (for the ease of backporting patches)


[`git-tags`]: https://github.com/lncm/docker-lnd/tags
[`opentimestamps`]: https://github.com/opentimestamps/opentimestamps-client/blob/master/doc/git-integration.md#usage
[Alpine]: https://github.com/lncm/docker-bitcoind/blob/6beae356ba16ee0297427c6401cd34f93044e256/0.19/Dockerfile#L11-L12
[`qemu`]: https://github.com/meeDamian/simple-qemu
[here]: https://github.com/lncm/docker-berkeleydb
[Docker Manifest]: https://github.com/reddcoin-project/docker-reddcoind/blob/master/.github/workflows/on-tag.yml#L178-L194
[build automatically]: https://github.com/reddcoin-project/docker-reddcoind/blob/master/.github/workflows/on-tag.yml
[auditable trace]: https://github.com/lncm/docker-bitcoind/runs/507498587?check_suite_focus=true
[Docker Hub]: https://github.com/reddcoin-project/docker-reddcoind/blob/master/.github/workflows/on-tag.yml#L167-L193
[Github Releases]: https://github.com/reddcoin-project/docker-reddcoind/blob/master/.github/workflows/on-tag.yml#L196-L203
[`strip`ped]: https://github.com/reddcoin-project/docker-reddcoind/blob/master/4.22/Dockerfile#L189


> **NOTE:** ZMQ `block` and `tx` ports are set to `28332` and `28333` respectively. 


## Tags

> **NOTE:** For an always up-to-date list see: https://hub.docker.com/repository/docker/reddcoincore/reddcoind/tags

* `v4.22.9.5`
* `v4.22.9.4`
* `v4.22.9`
* `v4.22.9rc2`
* `v4.22.9rc1`
* `v4.22.8`
* `v4.22.7`


## Usage

### Pull

First pull the image from [Docker Hub]:

```bash
docker pull reddcoincore/reddcoind:v4.22.9.5
```

> **NOTE:** Running above will automatically choose native architecture of your CPU.

[Docker Hub]: https://hub.docker.com/repository/docker/reddcoincore/reddcoind

Or, to pull a specific CPU architecture:

```bash
docker pull reddcoincore/reddcoind:v4.22.9.5-arm64v8
```

#### Start

First of all, create a directory in your home directory called `.reddcoin`

Next, create a config file. You can take a look at the following sample: thebox-compose-system ([1](https://github.com/lncm/thebox-compose-system/blob/master/bitcoin/bitcoin.conf)).

Some guides on how to configure reddcoin can be found [here](https://github.com/reddcoin-project/reddcoin/blob/master/doc/reddcoin-conf.md) (reddcoin git repo)

Then to start reddcoind, run:

```bash
docker run  -it  --rm  --detach \
    -v ~/.reddcoin:/home/reddcoind/.reddcoin \
    -p 45444:45444 \
    -p 18444:18444 \
    -p 28333:28333 \
    --name reddcoind \
    reddcoincore/reddcoind:v4.22.9.5
```

That will run reddcoind such that:

* all data generated by the container is stored in `~/.reddcoin` **on your host machine**,
* RPC will only be reachable from inside the container (see [RPC access](#rpc-access) to expose it),
* port `45444` will be reachable for the peer-to-peer communication,
* port `28332` will be reachable for ZMQ **block** notifications,
* port `28333` will be reachable for ZMQ **transaction** notifications,
* created container will get named `reddcoind`,
* within the container, `reddcoind` binary is run as unprivileged user `reddcoind` (`UID=1000`),
* that command will run the container in the background and print the ID of the container being run.


#### Interact

To issue any commands to a running container, do:

```bash
docker exec -it reddcoind BINARY COMMAND
```

Where:
* `BINARY` is either `reddcoind`, `reddcoin-cli`, `reddcoin-tx`, (or `reddcoin-wallet` on `v0.18+`) and
* `COMMAND` is something you'd normally pass to the binary   

Examples:

```bash
docker exec -it reddcoind reddcoind --help
docker exec -it reddcoind reddcoind --version
docker exec -it reddcoind reddcoin-cli --help
docker exec -it reddcoind reddcoin-cli -getinfo
docker exec -it reddcoind reddcoin-cli getblockcount
```

#### RPC access

By default the image sets no RPC username or password, and RPC only listens inside the container. `reddcoind` then uses cookie authentication (a `.cookie` file in the data directory), so `docker exec reddcoind reddcoin-cli ...` works without any credentials.

To reach RPC from the host or from other containers, set all of these when the container is first created:

| Variable | Example | Purpose |
|---|---|---|
| `RPC_USERNAME` | `reddcoinrpc` | RPC user name. Must be set together with `RPC_PASSWORD` |
| `RPC_PASSWORD` | a long random string | RPC password |
| `RPC_BIND` | `0.0.0.0` | Listen on the container's network interface, not just inside the container |
| `RPC_ALLOW_IP` | `172.16.0.0/12` | Addresses allowed to connect. `172.16.0.0/12` covers Docker's default networks, which is where connections from other containers, and from the host through a published port, come from |

Publish the RPC port on the host's loopback interface only, for example `-p 127.0.0.1:45443:45443`, unless other machines need to reach it.

> **NOTE:** These variables are only used when `reddcoin.conf` does not exist yet. An existing config file is never rewritten: edit it, or delete it to have it regenerated. Older versions of this image wrote `rpcpassword=rpcpassword` and `rpcallowip=0.0.0.0/0` into `reddcoin.conf`. The container now logs a warning at startup when it finds settings like these.

### Docker Compose
Here is a docker-compose.yml for mainnet
```yaml
version: '3'
services:
  reddcoin:
    container_name: reddcoind
    user: 1000:1000
    image: reddcoincore/reddcoind:v4.22.9.5
    volumes:
      - ./reddcoin:/home/reddcoind/.reddcoin
    restart: on-failure
    environment:
    - RPC_SERVER=1
    - RPC_USERNAME=[create a user name]
    - RPC_PASSWORD=[UseALongAndHardToGuessPassWord]
    - RPC_PORT=45443
    - RPC_BIND=0.0.0.0
    - RPC_ALLOW_IP=172.16.0.0/12
    stop_grace_period: 15m30s
    ports:
      - "127.0.0.1:45443:45443"
      - "45444:45444"
      - "28332:28332"
      - "28333:28333"
```
First, ensure that the `reddcoin/` folder is in the directory containing docker-compose.yml.
Then, Docker Compose will mount the `reddcoin/` folder to `/home/reddcoind/.reddcoin`.

#### Troubleshooting

##### Reddcoind isn't starting

Here are some possible reasons why.

###### Permissions for the reddcoin data directory is not correct

The permissions for the reddcoin data direct is assumed to be UID 1000 (first user). 

If you have a different setup, please do the following

```bash
# where ".reddcoin" is the data directory
sudo chown -R 1000.1000 $HOME/.reddcoin
```

