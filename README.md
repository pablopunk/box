# box — Proxmox LXCs on demand for your agents

```sh
curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
```

That's the whole install. It clones this repo to `~/.local/share/box`, links `box` into `~/.local/bin`, copies the skill into `~/.agents/skills` and `~/.claude/skills` (once per real location — symlinked skills dirs are detected, never double-installed), so synced skills work across machines. Each machine needs `box` installed and `~/.local/bin` on its PATH. The installer then walks you through the guided `box init` TUI: Proxmox host, SSH key, read-only checks, template download, golden build.

## Example

```sh
box new --mem 2048 --ttl 2h --name scratch    # -> 9101 192.168.1.57
box exec current -- 'uname -a && docker --version'
box ssh current
box shot current ./shot.png                   # Xvfb :99 screenshot
box stop current; box resume current --ttl 1h
box kill current --yes
box gc                                        # dry run; --expired stops, --destroy --yes deletes
```

The golden template includes Chromium, `xdg-open`, and an Xvfb display for GUI tasks, plus common networking and archive utilities. Start the display with `box shot`, then run GUI commands with `DISPLAY=:99`. Existing golden templates need `box golden build --force` to pick up package changes; Proxmox may refuse a rebuild while boxes still reference the template.
