Release notes
=============

Notes for the `reddcoincore/reddcoind` images built from this repo, newest first. For what changed in
Reddcoin Core itself, see the [upstream releases](https://github.com/reddcoin-project/reddcoin/releases).


## v4.22.9.5

Packages [Reddcoin Core v4.22.9.5](https://github.com/reddcoin-project/reddcoin/releases/tag/v4.22.9.5).

### Action required

* **RPC is no longer reachable from outside the container by default.** The image used to ship
  `rpcuser=rpcusername`, `rpcpassword=rpcpassword`, `rpcallowip=0.0.0.0/0` and `rpcbind=0.0.0.0`, so a
  published RPC port accepted those well-known credentials from any address. A new container now keeps RPC
  inside the container and uses cookie authentication, so `docker exec reddcoind reddcoin-cli ...` keeps
  working without credentials. To reach RPC from the host or other containers, set `RPC_USERNAME`,
  `RPC_PASSWORD`, `RPC_BIND=0.0.0.0` and `RPC_ALLOW_IP` when the container is first created, and publish the
  port on your loopback interface, for example `-p 127.0.0.1:45443:45443`. See "RPC access" in the README.

* **Existing nodes keep their current settings.** `setup.sh` has never rewritten an existing
  `reddcoin.conf`, so a node created by an older image keeps the old credentials and open `rpcallowip`.
  The container now prints a warning at every start when it finds them. To pick up the new defaults, stop
  the node, delete `reddcoin.conf` from the data directory, and start it again.

* **Check where your data actually is.** The README used to mount the host directory at `/data/.reddcoin`,
  which the image never uses. Nodes started that way keep their chain data in an anonymous Docker volume,
  and any `reddcoin.conf` in the host directory was ignored. The correct path is
  `/home/reddcoind/.reddcoin`. To find the volume and copy the data to the host directory:

  ```bash
  # the volume mounted at /home/reddcoind/.reddcoin is the one holding the chain data
  docker inspect reddcoind -f '{{range .Mounts}}{{.Destination}} <- {{.Type}} {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{"\n"}}{{end}}'

  docker stop -t 600 reddcoind
  docker run --rm -v <volume>:/from -v ~/.reddcoin:/to alpine sh -c 'cp -a /from/. /to/'
  ```

  `cp -a` keeps the files owned by UID 1000, which the image runs as. Keep the old volume until the node
  has started from the copy, then mount `~/.reddcoin` at `/home/reddcoind/.reddcoin` as the README shows.

### Fixed

* **`docker stop` now shuts the node down cleanly.** `setup.sh` ran `reddcoind` as a child of bash, which
  stayed PID 1 and never passed on the stop signal, so every stop ran out its timeout and killed the node,
  risking database corruption. `reddcoind` is now started with `exec` and receives the signal itself.
  A synced node can take a while to save its state on shutdown, so allow for that: the compose example uses
  `stop_grace_period`, and `docker stop` takes `-t`, as in `docker stop -t 600 reddcoind`.

* **The node no longer crashes when checking proof of work (RED-145).** 4.22.9.5 checks proof of work with
  scrypt, which puts a 128 KiB scratchpad on the stack, and musl gives threads other than the main one a
  128 KiB stack. An image built without this fix exits with 139 right after startup on testnet and regtest,
  and after about 44,000 headers on mainnet. The binaries are now linked with a 1 MiB thread stack.

* **The RPC password no longer appears in `docker logs`.** `setup.sh` traced every command it ran,
  including the one writing the password into the config.

### Added

* `scripts/test-rpc.sh` checks the RPC behaviour of a built image: the container-only default, cookie
  authentication, credentials having to be set in pairs, address filtering, the warning above, and that the
  password stays out of the logs.
* `scripts/test-networks.sh` starts a built image on mainnet, testnet and regtest, and has each node sync
  headers or mine blocks, so proof of work is checked on threads other than the main one.

### Build and release pipeline

* Release tags may now carry build numbers of more than one digit (`+build10` and up).
* GitHub releases are created with the `gh` CLI, replacing an unmaintained action that used the retired
  `set-output` command.
* Workflows write to `$GITHUB_ENV` instead of the retired `set-env` command, and `actions/checkout`,
  `actions/upload-artifact` and `actions/download-artifact` are updated to versions that run on Node 24.
