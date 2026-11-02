---
name: box
description: Proxmox LXCs on demand for agents. Spin up disposable Debian LXC sandboxes on any Proxmox host with the `box` CLI — new/exec/ssh/cp/snap/stop/resume/kill, TTL, mise-managed runtimes, Docker, headless Chromium and an Xvfb GUI screenshot path. Use when the user wants a throwaway Linux box, an isolated place to run web workflows, take browser screenshots, build studies, or run untrusted/experimental code, or says "box", "sandbox", "spin up a box". Keeps browser windows and heavy processes off the user's machine.
---

# box

Proxmox LXCs on demand for your agents. Ephemeral unprivileged Debian containers, linked-cloned from one golden template over SSH to the PVE host. Use-and-destroy by design.

**Full CLI reference: `box -h`** — it documents every command, flag and semantic. This file is the short version, plus how agents should use it.

## One-time setup

```sh
curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
```

Installs `box` in `~/.local/bin`, copies this skill, and runs the guided `box init` TUI (Proxmox host, SSH key, read-only checks, template download, golden build). Run `box` from PATH; install it on each machine and add `~/.local/bin` to PATH. Prereq: SSH to the PVE host with key auth. Flags (`box init --host …`) skip the TUI for scripts. The PVE host is usually on a LAN: off that network, reach it over Tailscale.

## Everyday flow

```sh
box new --name unmod-1234 --mem 2048 --tools "node@24 pnpm"   # -> "<id> <ip>", sets current
box exec current -- uname -a                  # run commands (stdin passes through)
box cp ./fixtures/ current:/root/fixtures/    # copy in; box cp current:/root/out.png ./ copies out
box snap https://app.example.com ./shot.png   # headless Chromium screenshot, run inside the box
box shot current ./display.png                # Xvfb :99 screenshot of the box's display
box ssh current                               # interactive shell
box kill current -f                           # destroy when done (use-and-destroy)
```

## When to use it

- **Use it for** web workflows in isolation: browser screenshots and before/after comparisons against a testing or PR-preview URL, driving a headless browser or Playwright, building or seeding studies, running untrusted or experimental code. Nothing opens on the user's machine.
- **Do not use it for** the code loop. Editing, git and CI-checked lint/tests stay in the local worktree; a box needs no repo clone for a browser run.
- **One box per task**, named for it (`--name unmod-1234`). Give a browser box `--mem 2048`. Always `box kill <id> -f` when the task ends; a forgotten box expires after its TTL but is not destroyed (`box gc --destroy -f`).

## Rules for agents

- **Secrets never go in arguments.** Fetch them on the user's machine and pipe them in: `printf %s "$TOKEN" | box exec current -- 'umask 077; cat > /root/.token'`, or `box cp` a file with mode 600. Boxes are disposable; kill them when done.
- **Runtimes come from mise.** `box new --tools "node@24 pnpm@12.4.2 go@latest"` or `box exec current -- 'mise use -g node@24'`. Do not `apt-get install` language runtimes.
- **Playwright** can use the system Chromium (`executablePath: $(which chromium)`); Chromium runs headless with `--no-sandbox` in the container.
- **Network:** a box reaches the internet, the testing environment and PR previews (`pr-<N>-maze-webapp.testingmazeco.cloud`). No VPN or local dev environment is needed for those.
- **Capacity:** at most `MAX_RUNNING` boxes run at once (default 6, set in `~/.config/box/config`). The host RAM guard is the real limit. If `box new` refuses, stop or kill one; override only with explicit human OK (`BOX_FORCE=1`).

## Key semantics

- Boxes: unprivileged LXC, `nesting=1,keyctl=1`, DHCP, TTL (default 1h; `box resume --ttl` extends it).
- Destructive commands (`kill`, `gc --destroy`) confirm on a TTY and require `-f` in scripts/agents.
- `box` only touches ids in its configured range with PVE tag `box`; anything else is refused.
- Resource guards refuse new boxes when host RAM/swap is tight, `MAX_RUNNING` is reached, or storage is full.
- **Backups:** PVE always backs up a container's rootfs (`backup=0` only works on extra mount points), so box excludes every box id, and the golden, from all-guest backup jobs before the CT exists. `box doctor` verifies it (exit 1 on FAIL); `box doctor --fix` adds missing exclusions. Run it after changing backup jobs on the host.
- Opt-in `--gpu` shares the host GPU via a DRM device bind — verify with a real encode, not just device listing.
- Golden image ships mise (with node LTS), Docker, Chromium, xdg-utils, rsync and Xvfb/Openbox/xdotool/scrot. GUI apps need the Xvfb display (start it with `box shot`, then use `DISPLAY=:99`). Heavy toolchains install per box with `--tools`, not in the golden. Rebuild it with `box golden build --force` after changing the provisioning script.
