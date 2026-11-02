# box — Proxmox LXCs on demand for your agents

```sh
curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
```

That's the whole install. It clones this repo to `~/.local/share/box`, links `box` into `~/.local/bin`, copies the skill into `~/.agents/skills` and `~/.claude/skills` (once per real location — symlinked skills dirs are detected, never double-installed), so synced skills work across machines. Each machine needs `box` installed and `~/.local/bin` on its PATH. The installer then walks you through the guided `box init` TUI: Proxmox host, SSH key, read-only checks, template download, golden build.

## Example

```sh
box new --mem 2048 --ttl 2h --name scratch --tools "node@24 pnpm"   # -> 9101 192.168.1.57
box exec current -- 'uname -a && node -v'
box cp ./site/ current:/root/site/             # rsync (scp fallback) over the PVE jump host
box snap https://example.com ./shot.png        # headless Chromium screenshot, run in the box
box shot current ./display.png                 # Xvfb :99 screenshot
box ssh current                                # tmux session; auto-reconnect + reattach
box job run current --lease 3h -- ./long.sh    # detached job with log and exit status
box extend current 2h
box stop current; box resume current --ttl 1h
box kill current --yes
box gc                                         # dry run; --expired stops, --destroy --yes deletes
```

The golden template includes mise, Chromium, `xdg-open`, rsync, and an Xvfb display for GUI tasks, plus common networking and archive utilities. Start the display with `box shot`, then run GUI commands with `DISPLAY=:99`. Existing golden templates need `box golden build --force` to pick up package changes; Proxmox may refuse a rebuild while boxes still reference the template.

## Tailscale, reconnection, cleanup

```sh
box init --force --host root@192.168.1.10 --alt root@100.x.y.z   # LAN first, Tailscale as fallback (init offers it)
box doctor                    # route, same host key on both addresses, host commands, golden, timer, leases, tmux
box doctor --e2e              # + create, ssh, tmux, lease, extend, destroy a throwaway box
box cleanup install           # host timer, REPORT-ONLY: nothing is stopped or deleted
box cleanup preview           # what it would do right now
box adopt all                 # let cleanup manage boxes made before leases existed
box cleanup mode stop         # then, once the preview looks right: stop expired boxes
box cleanup mode destroy      # ...and destroy them 24h after expiry (asks for confirmation)
```

- **Routes:** `PVE_HOST` is tried first, then `PVE_HOST_ALT`. Both use one pinned host key (`~/.box/known_hosts_pve`), so a different machine behind either address is refused. LAN is preferred again as soon as it answers.
- **Sessions:** `box ssh` runs a tmux session inside the box (tmux ships in the golden image and is installed on demand in older boxes). If the connection drops it reconnects, re-picks the route and reattaches. `--plain` gives ordinary ssh. Commands are never rerun automatically after a drop; use `box job run` for work that must survive.
- **Leases:** a box lives `--ttl` (default 1h) past its last activity, never longer than `MAX_LIFETIME` (7d) from creation. Cleanup waits `GRACE` (10m) past expiry, stops the box, and destroys it `DESTROY_AFTER` (24h) after expiry. It only touches boxes registered on the host whose metadata agrees, rechecks under a per-box lock, and holds boxes that have snapshots.
- **Interrupted `box new`:** the host keeps building after the client drops; the client asks the host about its request id and either returns the finished box or tells you exactly what is left. It never creates a second one.
- Tests: `tests/run.sh` (no Proxmox needed).

`MAX_RUNNING` (default 6) and the other limits live in `~/.config/box/config`.
