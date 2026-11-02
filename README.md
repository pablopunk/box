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
box stop current; box resume current --ttl 1h
box kill current --yes
box gc                                         # dry run; --expired stops, --destroy --yes deletes
```

The golden template includes mise, Chromium, `xdg-open`, rsync, and an Xvfb display for GUI tasks, plus common networking and archive utilities. Start the display with `box shot`, then run GUI commands with `DISPLAY=:99`. Existing golden templates need `box golden build --force` to pick up package changes; Proxmox may refuse a rebuild while boxes still reference the template.

## Tailscale and cleanup

```sh
box init --force --host root@<lan-ip> --alt root@<tailscale-ip>   # LAN first, Tailscale as fallback
box doctor [--e2e]                                                 # check routes, host, leases, tmux, backups
box cleanup install                                                # host timer, report-only until you opt in
```

`box ssh` reconnects and reattaches by itself if the connection drops, switching between LAN and Tailscale as needed. Boxes expire after their lease (`--ttl`, renewed by activity); `box cleanup mode stop|destroy` lets the host timer act on expired boxes. Details: `box -h`. Tests: `tests/run.sh`.

`MAX_RUNNING` (default 6) and the other limits live in `~/.config/box/config`.
