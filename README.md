# box — Proxmox LXCs on demand for your agents

Disposable Debian containers on your Proxmox host, driven over SSH. Create one, run things in it, destroy it.

```sh
curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
```

This puts `box` in `~/.local/bin` (keep it on your PATH), installs the agent skill, and starts `box init`.

```sh
box init                              # Proxmox host, SSH key, checks, template, golden image
box init --force --host root@<lan-ip> --alt root@<tailscale-ip>   # add a Tailscale fallback
```

```sh
box new --name scratch --ttl 2h       # create a box -> prints "<id> <ip>"
box exec current -- 'uname -a'        # run a command
box ssh current                       # tmux shell; reconnects if the connection drops
box cp ./site/ current:/root/site/    # copy files in or out
box job run current -- ./long.sh      # detached job with log and exit status
box list                              # boxes, status, time left
box kill current -f                   # destroy it
box doctor                            # check routes, host, leases, backups
box cleanup install                   # host timer for expired boxes (report-only until you opt in)
```

Boxes expire after their lease (`--ttl`, renewed by activity). `box -h` lists everything else.
