---
name: box
description: Proxmox LXCs on demand for agents. Spin up disposable Debian LXC sandboxes on any Proxmox host with the `box` CLI — new/exec/ssh/stop/resume/kill, TTL, Docker, dev toolchains and an Xvfb GUI screenshot path. Use when the user wants a throwaway Linux box, an isolated place to run untrusted/experimental code, a GUI/browser test display, or says "box", "sandbox", "spin up a box".
---

# box

Proxmox LXCs on demand for your agents. Ephemeral unprivileged Debian containers, linked-cloned from one golden template over SSH to the PVE host. Use-and-destroy by design.

**Full CLI reference: `box -h`** — it documents every command, flag and semantic. This file is just a summary.

## One-time setup

```sh
curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
```

Installs `box`, links this skill, and runs the guided `box init` TUI (Proxmox host, SSH key, read-only checks, template download, golden build). Prereq: SSH to the PVE host with key auth. Flags (`box init --host …`) skip the TUI for scripts.

## Everyday flow

```sh
box new --name scratch            # -> "<id> <ip>", sets current
box exec current -- uname -a      # run commands
box ssh current                   # interactive shell
box shot current ./shot.png       # Xvfb :99 screenshot
box kill current -f               # destroy (use-and-destroy)
```

## Key semantics

- Boxes: unprivileged LXC, `nesting=1,keyctl=1`, DHCP, TTL (default 1h, expired ≠ auto-destroyed; `box gc --destroy -f` cleans up).
- Destructive commands (`kill`, `gc --destroy`) confirm on a TTY and require `-f` in scripts/agents.
- `box` only touches ids in its configured range with PVE tag `box`; anything else is refused.
- Resource guards refuse new boxes when host RAM/swap is tight or storage is full.
- Opt-in `--gpu` shares the host GPU via a DRM device bind — verify with a real encode, not just device listing.
- Golden image ships Docker, node/python/go toolchains and Xvfb/Openbox/xdotool/scrot. Heavy toolchains install per box, not in the golden.
