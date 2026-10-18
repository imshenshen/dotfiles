#!/bin/bash
#
# tailcat-supervisor
#
# Surge "external" policy wrapper. Keeps the tailcat forwarder alive and
# restarts it when the SOCKS5 path through the tunnel stops responding.
#
# Surge launches this script instead of tailcat directly and passes the
# configured args; all args are forwarded to tailcat unchanged.
#
# Optional environment overrides (Surge does not set these):
#   TAILCAT_BIN                     default /opt/homebrew/bin/tailcat
#   TAILCAT_TEST_URL                default http://erp.jd.com
#   TAILCAT_FALLBACK_URL            default http://www.baidu.com (empty to disable)
#   TAILCAT_SUPERVISOR_INTERVAL     seconds between probes (default 15)
#   TAILCAT_SUPERVISOR_FAILS        consecutive failures before restart (default 3)
#   TAILCAT_SUPERVISOR_TIMEOUT      max seconds per probe (default 12)
#   TAILCAT_SUPERVISOR_LOG          log path
#   TAILCAT_SUPERVISOR_STANDALONE=1 do not exit when the parent exits
#
set -u
umask 077

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

BIN="${TAILCAT_BIN:-/opt/homebrew/bin/tailcat}"
TEST_URL="${TAILCAT_TEST_URL:-http://erp.jd.com}"
FALLBACK_URL="${TAILCAT_FALLBACK_URL-http://www.baidu.com}"
INTERVAL="${TAILCAT_SUPERVISOR_INTERVAL:-15}"
FAIL_THRESHOLD="${TAILCAT_SUPERVISOR_FAILS:-3}"
TIMEOUT="${TAILCAT_SUPERVISOR_TIMEOUT:-12}"
LOG="${TAILCAT_SUPERVISOR_LOG:-${HOME:-/tmp}/Library/Logs/tailcat-supervisor.log}"

LSOF=/usr/sbin/lsof
PS=/bin/ps
CURL=/usr/bin/curl
NC=/usr/bin/nc

TAILCAT_ARGS=("$@")

# Derive the local listen port from a forward mapping such as "1088:11080".
PORT=""
for a in "${TAILCAT_ARGS[@]}"; do
  case "$a" in
    [0-9]*:[0-9]*) PORT="${a%%:*}" ;;
  esac
done
PORT="${PORT:-${TAILCAT_PROXY_PORT:-1088}}"

LOCKDIR="/tmp/tailcat-supervisor.${PORT}.lock"
CHILD=""

mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() {
  if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG" "$LOG.old" 2>/dev/null
  fi
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$LOG" 2>/dev/null
}

acquire_lock() {
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    old=""
    i=0
    while [ "$i" -lt 10 ]; do
      old=$(cat "$LOCKDIR/pid" 2>/dev/null)
      [ -n "$old" ] && break
      sleep 0.1
      i=$((i + 1))
    done
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      log "another supervisor is already running (pid $old), exiting"
      exit 0
    fi
    # Stale lock left by a killed process.
    rm -rf "$LOCKDIR"
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
      log "failed to acquire lock $LOCKDIR, exiting"
      exit 1
    fi
  fi
  printf '%s\n' "$$" >"$LOCKDIR/pid"
}

release_lock() {
  if [ "$(cat "$LOCKDIR/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCKDIR"
  fi
}

listener_pids() {
  "$LSOF" -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null
}

wait_port_free() {
  i=0
  while [ "$i" -lt 25 ]; do
    [ -z "$(listener_pids)" ] && return 0
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

# Kill a tailcat left on our port by a previous supervisor run.
# Never touch a non-tailcat listener.
cleanup_stale_listener() {
  pids=$(listener_pids)
  [ -z "$pids" ] && return 0

  for p in $pids; do
    cmd=$("$PS" -o command= -p "$p" 2>/dev/null)
    case "$cmd" in
      *tailcat*[Ff]orward*"${PORT}:"*)
        log "killing stale tailcat on port $PORT (pid $p)"
        kill -TERM "$p" 2>/dev/null
        ;;
      *)
        log "port $PORT is held by a non-tailcat process (pid $p): $cmd"
        return 1
        ;;
    esac
  done

  wait_port_free && return 0

  for p in $pids; do
    cmd=$("$PS" -o command= -p "$p" 2>/dev/null)
    case "$cmd" in
      *tailcat*[Ff]orward*"${PORT}:"*) kill -KILL "$p" 2>/dev/null ;;
    esac
  done
  wait_port_free
}

stop_child() {
  [ -z "$CHILD" ] && return 0
  if kill -0 "$CHILD" 2>/dev/null; then
    kill -TERM "$CHILD" 2>/dev/null
    i=0
    while kill -0 "$CHILD" 2>/dev/null && [ "$i" -lt 50 ]; do
      sleep 0.1
      i=$((i + 1))
    done
    if kill -0 "$CHILD" 2>/dev/null; then
      kill -KILL "$CHILD" 2>/dev/null
    fi
  fi
  wait "$CHILD" 2>/dev/null
  CHILD=""
}

start_child() {
  cleanup_stale_listener || return 1
  # Do not log the args: the tailcat address and key name are sensitive.
  log "starting tailcat $BIN on port $PORT"
  "$BIN" "${TAILCAT_ARGS[@]}" >>"$LOG" 2>&1 &
  CHILD=$!

  i=0
  while [ "$i" -lt 100 ]; do
    if ! kill -0 "$CHILD" 2>/dev/null; then
      wait "$CHILD" 2>/dev/null
      CHILD=""
      log "tailcat exited during startup"
      return 1
    fi
    if "$NC" -z -w 1 127.0.0.1 "$PORT" >/dev/null 2>&1; then
      log "tailcat is listening on 127.0.0.1:$PORT (pid $CHILD)"
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  log "tailcat did not listen on port $PORT within 10s"
  stop_child
  return 1
}

probe_url() {
  /usr/bin/env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy \
    "$CURL" -sS -o /dev/null --max-time "$TIMEOUT" \
    --socks5-hostname "127.0.0.1:$PORT" --noproxy '' "$1" 2>>"$LOG"
}

# End-to-end check through the same SOCKS5 listener Surge uses.
# Returns 0 if TEST_URL works, 2 if only the fallback works (tunnel is up but
# the target service is down), 1 if the tunnel itself is broken.
#
# Do not add --connect-timeout here: with SOCKS5 it also bounds the time spent
# connecting to the final destination, and a freshly started tailcat may need
# several seconds to establish its path.
probe() {
  probe_url "$TEST_URL" && return 0
  if [ -n "$FALLBACK_URL" ] && probe_url "$FALLBACK_URL"; then
    return 2
  fi
  return 1
}

parent_still_there() {
  [ "${TAILCAT_SUPERVISOR_STANDALONE:-0}" = "1" ] && return 0
  ppid=$("$PS" -o ppid= -p $$ 2>/dev/null | tr -d ' ')
  [ -z "$ppid" ] && return 0
  [ "$ppid" != "1" ]
}

cleanup() {
  trap - EXIT INT TERM HUP
  stop_child
  release_lock
  log "supervisor stopped"
}

main() {
  log "supervisor starting (port $PORT, test $TEST_URL, interval ${INTERVAL}s, threshold $FAIL_THRESHOLD)"
  acquire_lock

  fail_count=0
  backoff=0
  fallback_logged=0

  while :; do
    if ! parent_still_there; then
      log "parent process exited, shutting down"
      break
    fi

    if [ -z "$CHILD" ] || ! kill -0 "$CHILD" 2>/dev/null; then
      if [ -n "$CHILD" ]; then
        wait "$CHILD" 2>/dev/null
        CHILD=""
        log "tailcat exited unexpectedly"
      fi
      if start_child; then
        fail_count=0
        backoff=0
        sleep 3   # let the tailcat path settle before probing
      else
        if [ "$backoff" -eq 0 ]; then backoff=5; else backoff=$((backoff * 2)); fi
        [ "$backoff" -gt 60 ] && backoff=60
        log "start failed, retrying in ${backoff}s"
        sleep "$backoff"
        continue
      fi
    fi

    probe_status=0
    probe || probe_status=$?
    if [ "$probe_status" -eq 0 ]; then
      if [ "$fail_count" -gt 0 ]; then
        log "probe OK again after $fail_count failure(s)"
      fi
      if [ "$fallback_logged" -eq 1 ]; then
        log "primary probe is OK again"
      fi
      fail_count=0
      fallback_logged=0
      backoff=0
    elif [ "$probe_status" -eq 2 ]; then
      # The tunnel works; the primary test URL is down. Do not restart tailcat.
      if [ "$fallback_logged" -eq 0 ]; then
        log "primary probe failed but fallback is OK; tunnel is healthy, not restarting"
      fi
      fail_count=0
      fallback_logged=1
      backoff=0
    else
      fallback_logged=0
      fail_count=$((fail_count + 1))
      log "probe failed ($fail_count/$FAIL_THRESHOLD) for $TEST_URL"
      if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
        log "restarting tailcat after $fail_count consecutive probe failures"
        stop_child
        fail_count=0
        if [ "$backoff" -gt 0 ]; then
          log "backing off ${backoff}s before restart"
          sleep "$backoff"
        fi
        if start_child; then
          backoff=0
          sleep 3
        else
          if [ "$backoff" -eq 0 ]; then backoff=5; else backoff=$((backoff * 2)); fi
          [ "$backoff" -gt 60 ] && backoff=60
          log "restart failed, next backoff ${backoff}s"
          sleep "$backoff"
        fi
        continue
      fi
    fi

    sleep "$INTERVAL"
  done
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP
main
