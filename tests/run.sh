#!/usr/bin/env bash
# Offline tests for box: the host-side library runs against a fake /etc/pve and a stub `pct`;
# route selection and the reconnect loop run against stubbed ssh. No Proxmox needed.
#   tests/run.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAILN=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAILN=$((FAILN+1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '        %s\n' "$2"; }
check() { # check <name> <cmd...>
  local n=$1; shift
  if "$@"; then ok "$n"; else bad "$n"; fi
}

# ---- extract the host library and build stubs
sed -n "/^read -r -d '' REMOTE_LIB/,/^REMOTE_EOF/p" "$ROOT/box" | sed '1d;$d' >"$T/lib.sh"
sed '$d' "$T/lib.sh" | sed '$d' >"$T/lib_nodispatch.sh"   # drop the "fn=$1; shift; r_$fn" dispatch
mkdir -p "$T/bin" "$T/pve/lxc" "$T/var" "$T/lock" "$T/ct"
cat >"$T/bin/pct" <<'STUB'
#!/usr/bin/env bash
# stub pct: state in $STUB/ct/<id>.{status,snaps}; config in $PVE_ETC/lxc/<id>.conf
cmd=$1; shift
echo "pct $cmd $*" >>"$STUB/calls"
case "$cmd" in
  status) echo "status: $(cat "$STUB/ct/$1.status" 2>/dev/null || echo stopped)";;
  stop|shutdown) echo stopped >"$STUB/ct/$1.status";;
  start) echo running >"$STUB/ct/$1.status";;
  clone) [ -f "$STUB/clonefail" ] && exit 1
         sed "s/^template: 1/hostname: new/" "$PVE_ETC/lxc/$1.conf" | grep -v '^template' >"$PVE_ETC/lxc/$2.conf"; echo stopped >"$STUB/ct/$2.status";;
  resize) ;;
  destroy) rm -f "$PVE_ETC/lxc/$1.conf" "$STUB/ct/$1.status";;
  listsnapshot) echo '`-> current                      You are here!'; [ -f "$STUB/ct/$1.snaps" ] && cat "$STUB/ct/$1.snaps"; true;;
  set) id=$1; shift
       while [ $# -gt 0 ]; do
         if [ "$1" = --tags ]; then sed -i "s/^tags:.*/tags: $2/" "$PVE_ETC/lxc/$id.conf"; grep -q '^tags:' "$PVE_ETC/lxc/$id.conf" || echo "tags: $2" >>"$PVE_ETC/lxc/$id.conf"; shift 2
         elif [ "$1" = --description ]; then
           f="$PVE_ETC/lxc/$id.conf"; grep -v '^#' "$f" >"$f.new" || true
           { printf '#%s\n' "$2"; cat "$f.new"; } >"$f"; rm -f "$f.new"; shift 2
         else shift; fi
       done;;
  exec) id=$1; shift; [ "$1" = -- ] && shift
        case "$*" in
          *"ip -4"*) echo "2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0";;
          *tmux*) [ -f "$STUB/notmux" ] && exit 1 || exit 0;;
          *) exit 0;;
        esac;;
esac
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' >"$T/bin/sleep"; cp "$T/bin/sleep" "$T/bin/timeout"
cat >"$T/bin/pvesh" <<'STUB'
#!/usr/bin/env bash
echo '[]'
STUB
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" STUB="$T" PVE_ETC="$T/pve" LOCK_DIR="$T/lock" BOX_VAR="$T/var"

NOW=$(date +%s)
# mkct <id> <status> <expires-offset> [ttl] [created-offset] [registered] [extra-desc]
mkct() {
  local id=$1 st=$2 eo=$3 ttl=${4:-3600} co=${5:--100} reg=${6:-yes} extra=${7:-} desc
  echo "$st" >"$T/ct/$id.status"
  desc="box1 owner_tester expires_$((NOW+eo)) name_t$id"
  [ "$ttl" = none ] || desc="$desc ttl_$ttl created_$((NOW+co))"
  desc="$desc$extra"
  printf '#%s\narch: amd64\nhostname: t%s\nmemory: 1024\ntags: box\n' "$desc" "$id" >"$T/pve/lxc/$id.conf"
  if [ "$reg" = yes ] && [ "$ttl" != none ]; then
    mkdir -p "$T/var/registry"; printf 'owner=tester created=%s\n' "$((NOW+co))" >"$T/var/registry/$id"
  fi
}
reset() { rm -rf "$T/pve/lxc" "$T/ct" "$T/var" "$T/lock" "$T/calls"; mkdir -p "$T/pve/lxc" "$T/ct" "$T/var" "$T/lock"; : >"$T/calls"; rm -f "$T/notmux"; }
# host <fn> [args]: run r_<fn> from the real library with test settings
host() {
  local fn=$1; shift
  bash -c "ID_MIN=9101; ID_MAX=9199; GOLDEN_CTID=9100; STORAGE=local-lvm; BRIDGE=vmbr0; FULL_CLONE=0; BOX_FORCE=1; MAX_LIFETIME_S=${MAX_LIFETIME_S:-604800}; GRACE_S=${GRACE_S:-600}; DESTROY_AFTER_S=${DESTROY_AFTER_S:-86400}; LEASE_RENEW=${LEASE_RENEW:-1}
$(cat "$T/lib.sh")" box-remote "$fn" "$@"
}
# hostf <function> [args]: call an internal library function directly
hostf() {
  local fn=$1; shift
  bash -c "ID_MIN=9101; ID_MAX=9199; GOLDEN_CTID=9100; STORAGE=local-lvm; BRIDGE=vmbr0; FULL_CLONE=0; BOX_FORCE=1; MAX_LIFETIME_S=604800; GRACE_S=600; DESTROY_AFTER_S=86400; LEASE_RENEW=1
$(cat "$T/lib_nodispatch.sh")
\"\$@\"" box-remote "$fn" "$@"
}
exp_of() { sed -n 's/.*expires_\([0-9]*\).*/\1/p' "$T/pve/lxc/$1.conf" | head -1; }
called() { grep -q -- "$1" "$T/calls"; }

echo "leases"
reset; mkct 9101 running 60 3600 -100
host renew 9101 >/dev/null 2>&1
e=$(exp_of 9101)
check "activity renews a managed box's lease to now+ttl" test "$e" -ge $((NOW+3590))
reset; mkct 9101 running 60 none
host renew 9101 >/dev/null 2>&1
check "legacy box (no lease metadata) is left untouched" test "$(exp_of 9101)" = $((NOW+60))
reset; mkct 9101 running 60 3600 -604000   # created 6.99 days ago, cap = created + 7d = now+800s
host renew 9101 >/dev/null 2>&1
e=$(exp_of 9101)
check "renewal is capped at created + MAX_LIFETIME" test "$e" -le $((NOW+810)) -a "$e" -ge $((NOW+60))
reset; mkct 9101 running 60 3600 -100
LEASE_RENEW=0 host renew 9101 >/dev/null 2>&1
check "IDLE_RENEW=0 disables renewal" test "$(exp_of 9101)" = $((NOW+60))
reset; mkct 9101 running 60 none
host extend 9101 7200 >/dev/null 2>&1
check "box extend adopts a legacy box and sets the lease" test "$(exp_of 9101)" -ge $((NOW+7190)) -a -f "$T/var/registry/9101"
reset; mkct 9101 running 60 none; mkct 9102 stopped 60 none
host adopt all 3600 >/dev/null 2>&1
check "box adopt all registers every legacy box" test -f "$T/var/registry/9101" -a -f "$T/var/registry/9102"

echo "resume"
reset; mkct 9101 stopped -5000 3600 -9000
host resume 9101 3600 >/dev/null 2>&1
n_set=$(grep -n 'pct set' "$T/calls" | head -1 | cut -d: -f1); n_start=$(grep -n 'pct start' "$T/calls" | head -1 | cut -d: -f1)
check "resume renews the lease before starting the box" test -n "$n_set" -a -n "$n_start" -a "${n_set:-9}" -lt "${n_start:-0}"
check "resumed box has a fresh lease" test "$(exp_of 9101)" -ge $((NOW+3590))

echo "cleanup safety"
reset
mkct 9101 running -3000 3600 -9000     # expired 50 min ago, registered
mkct 9102 running -100 3600 -9000      # expired 100s ago: inside the grace period
mkct 9103 running -3000 none           # expired, legacy / unregistered
mkct 9104 running 600 3600 -100        # alive
out=$(host cleanup report 2>&1)
check "report mode lists the expired box" grep -q 'report 9101' <<<"$out"
check "report mode never stops anything" test ! -s <(grep -E 'pct (stop|shutdown|destroy)' "$T/calls")
out=$(host cleanup stop 2>&1)
check "stop mode stops the expired registered box" grep -q 'stopping expired 9101' <<<"$out"
check "box inside the grace period is not touched" test "$(cat "$T/ct/9102.status")" = running
check "unregistered (legacy) box is skipped" grep -q 'skip 9103: not in the registry' <<<"$out"
check "unregistered box is still running" test "$(cat "$T/ct/9103.status")" = running
check "live box is not touched" test "$(cat "$T/ct/9104.status")" = running
reset
mkct 9101 stopped -90000 3600 -99999    # stopped, expired > DESTROY_AFTER ago
mkct 9102 stopped -90000 3600 -99999    # same, but has a snapshot
printf '%s\n' '`-> before-risky   2025-01-01 snapshot' >"$T/ct/9102.snaps"
mkct 9103 stopped -3000 3600 -9000      # stopped, expired recently: waits
mkct 9104 stopped -90000 none           # stopped, expired long ago, legacy
out=$(host cleanup stop 2>&1)
check "stop mode never destroys" test ! -s <(grep 'pct destroy' "$T/calls")
out=$(host cleanup destroy 2>&1)
check "destroy mode destroys a long-expired stopped box" test ! -e "$T/pve/lxc/9101.conf"
check "registry entry removed with the box" test ! -e "$T/var/registry/9101"
check "box with snapshots is held, not destroyed" test -e "$T/pve/lxc/9102.conf"
check "recently expired stopped box waits" test -e "$T/pve/lxc/9103.conf"
check "legacy box is never destroyed by cleanup" test -e "$T/pve/lxc/9104.conf"
check "only box-managed CTs are touched (golden/foreign ids ignored)" test "$(grep -c 'pct destroy' "$T/calls")" = 1

echo "cleanup vs. resume/renew race"
reset; mkct 9101 running -3000 3600 -9000
# scan says expired; before the action runs the owner renews. The under-lock recheck must back off.
host renew 9101 >/dev/null 2>&1
out=$(hostf reap_one 9101 stop 600 1 2>&1)
check "renewal after the scan makes cleanup skip the box" grep -q 'skip 9101: lease renewed' <<<"$out"
check "...and the box keeps running" test "$(cat "$T/ct/9101.status")" = running
reset; mkct 9101 running -3000 3600 -9000
( exec 8>"$T/lock/box-ct-9101.lock"; flock 8; sleep_real=1; /bin/sleep 3 ) &
holder=$!; /bin/sleep 0.5
out=$(hostf reap_one 9101 stop 600 1 2>&1)
check "a box whose lock is held (resume/renew in flight) is left alone" grep -q 'busy 9101' <<<"$out"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check "...and is still running" test "$(cat "$T/ct/9101.status")" = running
reset; mkct 9101 running -3000 3600 -9000
out=$(hostf reap_one 9101 stop 600 1 2>&1)
check "expired and unlocked: cleanup stops it" grep -q 'stopping expired 9101' <<<"$out"
reset; mkct 9101 running -3000 3600 -9000; sed -i 's/^tags: box$/tags: other/' "$T/pve/lxc/9101.conf"
out=$(hostf reap_one 9101 stop 600 1 2>&1)
check "a CT that lost its box tag is never touched" grep -q 'no longer a box' <<<"$out"
reset; mkct 9101 running -3000 3600 -9000; printf 'owner=tester created=1\n' >"$T/var/registry/9101"
out=$(hostf reap_one 9101 stop 600 1 2>&1)
check "registry that disagrees with the CT's metadata blocks cleanup" grep -q 'not in the registry' <<<"$out"

echo "request reconciliation"
reset; mkct 9101 running 600 3600 -100 yes " req_abc123"
check "find_req locates the box created by a request id" test "$(hostf find_req abc123 2>/dev/null)" = 9101
out=$(host reconcile abc123 2>&1)
check "reconcile reports a finished creation with its address" test "$out" = "ready 9101 10.0.0.5"
out=$(host reconcile nosuchreq 2>&1)
check "reconcile reports 'none' when nothing was created" test "$out" = none
reset; mkct 9101 stopped 600 3600 -100 yes " req_zzz"
out=$(host reconcile zzz 2>&1)
check "reconcile flags a created-but-not-running box as partial" test "$out" = "partial 9101"

echo "creation"
reset; printf 'template: 1\ntags: boxgolden\nhostname: g\nmemory: 2048\nrootfs: local-lvm:vm-9100-disk-0,size=8G\n' >"$T/pve/lxc/9100.conf"
out=$(host new demo 1 1024 8 3600 tester 0 reqXYZ 2>/dev/null); rc=$?
check "new creates the box and prints id and ip" test "$out" = "9101 10.0.0.5"
check "new records lease, request id and registry entry" bash -c "grep -q 'ttl_3600' $T/pve/lxc/9101.conf && grep -q 'req_reqXYZ' $T/pve/lxc/9101.conf && grep -q 'created=' $T/var/registry/9101"
check "new tags the CT as a box" grep -q '^tags: box' "$T/pve/lxc/9101.conf"
out=$(host new demo 1 1024 8 3600 tester 0 reqXYZ 2>/dev/null)
check "repeating the same request id returns the same box, no second CT" test "$out" = "9101 10.0.0.5" -a ! -e "$T/pve/lxc/9102.conf"
touch "$T/clonefail"
out=$(host new demo2 1 1024 8 3600 tester 0 reqFAIL 2>/dev/null); rc=$?
check "a failed creation is rolled back (no CT, no registry entry)" test "$rc" != 0 -a ! -e "$T/pve/lxc/9102.conf" -a ! -e "$T/var/registry/9102"
rm -f "$T/clonefail"

echo "host checks"
reset; mkct 9101 running 600 3600 -100; mkct 9102 running 600 none
touch "$T/notmux"
out=$(host hostcheck 2>&1)
check "hostcheck warns about legacy boxes" grep -q 'predate leases' <<<"$out"
check "hostcheck warns about boxes without tmux" grep -q 'no tmux in running box' <<<"$out"

# ---- client side (box sourced, ssh stubbed)
echo "routes"
export BOX_CONFIG="$T/none" BOX_STATE="$T/state"
mkdir -p "$T/state"
# shellcheck disable=SC1090
( . "$ROOT/box"; set +e
  PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=root@100.64.0.1; STATE_DIR="$T/state"
  up="$T/up"
  timeout() { shift; "$@"; }
  ssh() { local a h; case "$1" in -O) return 0;; esac; for a in "$@"; do h=$a; done; [ "$h" = true ] && h=${@: -2:1}; grep -qx "$h" "$up"; }
  log() { echo "$*" >>"$T/route.log"; }
  rm -f "$T/state/route"
  printf 'root@10.0.0.1\nroot@100.64.0.1\n' >"$up"; PVE_ACTIVE=""; route_try; echo "both up: $PVE_ACTIVE" >"$T/r1"
  printf 'root@100.64.0.1\n' >"$up"; PVE_ACTIVE=""; route_try; echo "lan down: $PVE_ACTIVE" >"$T/r2"
  printf 'root@10.0.0.1\nroot@100.64.0.1\n' >"$up"; PVE_ACTIVE=""; route_try; echo "recent fallback: $PVE_ACTIVE" >"$T/r3"
  touch -d '2 minutes ago' "$T/state/route"; PVE_ACTIVE=""; route_try; echo "after 30s: $PVE_ACTIVE" >"$T/r4"
  : >"$up"; PVE_ACTIVE=""; route_try && echo "none: $PVE_ACTIVE" >"$T/r5" || echo "none: unreachable" >"$T/r5"
)
check "LAN preferred when both addresses answer" grep -q 'both up: root@10.0.0.1' "$T/r1"
check "falls back to the alternate when LAN is down" grep -q 'lan down: root@100.64.0.1' "$T/r2"
check "stays on the alternate briefly (no repeated connect timeouts)" grep -q 'recent fallback: root@100.64.0.1' "$T/r3"
check "returns to LAN once it answers again" grep -q 'after 30s: root@10.0.0.1' "$T/r4"
check "reports unreachable when neither answers" grep -q 'none: unreachable' "$T/r5"
check "route changes are logged" grep -q 'LAN unreachable, using alternate' "$T/route.log"
check "...including recovery" grep -q 'back on LAN' "$T/route.log"

echo "reconnecting ssh"
# needs a tty for the interactive path
script -qec "bash -c '. $ROOT/box; set +e; STATE_DIR=$T/state; SSH_KEY=/dev/null; PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=; RECONNECT_TRIES=5; IDLE_RENEW=0; n=0
route_try(){ PVE_ACTIVE=root@10.0.0.1; }; rcall(){ echo 10.0.0.5; }; ct_ssh_opts(){ CT_OPTS=(-o x=y); }
ssh(){ n=\$((n+1)); echo \"ssh#\$n: \$*\" >>$T/ssh2.log; if [ \$n -lt 3 ]; then return 255; fi; return 0; }
cmd_ssh 9101; echo \"rc=\$? attempts=\$n\" >$T/ssh2.res'" /dev/null >/dev/null 2>&1
check "interactive ssh reconnects after transport failures (255) and then exits cleanly" grep -q 'rc=0 attempts=3' "$T/ssh2.res"
check "each attempt attaches the tmux session" test "$(grep -c 'tmux new-session -A' "$T/ssh2.log")" = 3
script -qec "bash -c '. $ROOT/box; set +e; STATE_DIR=$T/state; SSH_KEY=/dev/null; PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=; RECONNECT_TRIES=5; IDLE_RENEW=0; n=0
route_try(){ PVE_ACTIVE=root@10.0.0.1; }; rcall(){ echo 10.0.0.5; }; ct_ssh_opts(){ CT_OPTS=(-o x=y); }
ssh(){ n=\$((n+1)); return 7; }
cmd_ssh 9101; echo \"rc=\$? attempts=\$n\" >$T/ssh3.res'" /dev/null >/dev/null 2>&1
check "a remote exit status is passed through, not retried" grep -q 'rc=7 attempts=1' "$T/ssh3.res"
rm -f "$T/ssh4.n"
script -qec "bash -c '. $ROOT/box; set +e; STATE_DIR=$T/state; SSH_KEY=/dev/null; PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=; RECONNECT_TRIES=3; IDLE_RENEW=0
route_try(){ PVE_ACTIVE=root@10.0.0.1; }; rcall(){ echo 10.0.0.5; }; ct_ssh_opts(){ CT_OPTS=(-o x=y); }
ssh(){ echo x >>$T/ssh4.n; return 255; }
( cmd_ssh 9101 ) 2>/dev/null; echo \"rc=\$? attempts=\$(wc -l <$T/ssh4.n)\" >$T/ssh4.res'" /dev/null >/dev/null 2>&1
check "gives up after RECONNECT_TRIES failed attempts" grep -Eq 'rc=1 attempts= *4' "$T/ssh4.res"
script -qec "bash -c '. $ROOT/box; set +e; STATE_DIR=$T/state; SSH_KEY=/dev/null; PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=; IDLE_RENEW=0; n=0
route_try(){ PVE_ACTIVE=root@10.0.0.1; }; rcall(){ echo 10.0.0.5; }; ct_ssh_opts(){ CT_OPTS=(-o x=y); }
ssh(){ n=\$((n+1)); echo \"\$*\" >$T/ssh5.log; return 0; }
cmd_ssh 9101 --plain; echo \"rc=\$? attempts=\$n\" >$T/ssh5.res'" /dev/null >/dev/null 2>&1
check "--plain runs ssh once" grep -q 'attempts=1' "$T/ssh5.res"
check "--plain does not use tmux" test "$(grep -c tmux "$T/ssh5.log")" = 0

echo "creation recovery"
( . "$ROOT/box"; set +e
  STATE_DIR="$T/state"; PVE_HOST=root@10.0.0.1; PVE_HOST_ALT=""
  route_try() { PVE_ACTIVE=root@10.0.0.1; }
  rm -f "$T/c"; rcall() { local c; c=$(cat "$T/c" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" >"$T/c"; case "$c" in 1) echo building;; 2) echo "ready 9101 10.0.0.5";; esac; }
  out=$(new_recover req1 2>/dev/null); echo "rc=$? out=$out" >"$T/rec1"
  rcall() { echo none; }
  new_recover req2 >/dev/null 2>"$T/rec2.err"; echo "rc=$?" >"$T/rec2"
  rcall() { echo "partial 9105"; }
  new_recover req3 >/dev/null 2>"$T/rec3.err"; echo "rc=$?" >"$T/rec3"
)
check "dropped creation: waits for the host, returns the finished box" grep -q 'rc=0 out=9101 10.0.0.5' "$T/rec1"
check "dropped creation, nothing built: reports it (rc 4)" grep -q 'rc=4' "$T/rec2"
check "...and says it is safe to run again" grep -q 'safe to run' "$T/rec2.err"
check "dropped creation, half built: rc 3" grep -q 'rc=3' "$T/rec3"
check "...and names the box to inspect" grep -q '9105' "$T/rec3.err"

echo
echo "passed $PASS, failed $FAILN"
[ "$FAILN" = 0 ]
