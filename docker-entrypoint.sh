#!/bin/bash
set -euo pipefail

# Upstream defaults logging.type to "console" via RSPAMD_LOG_TYPE=console.
RSPAMD_LOG_TYPE="${RSPAMD_LOG_TYPE:-console}"
RSPAMD_LOG_FILE="${RSPAMD_LOG_FILE:-/var/log/rspamd/rspamd.log}"

# Re-emit the log file to stdout (for alloy/Loki) when logging to a file.
RSPAMD_LOG_TAIL="${RSPAMD_LOG_TAIL:-true}"

# In-process log rotation. The logrotate config is supplied by the chart
# (mounted from the ConfigMap); only the run interval is set here.
RSPAMD_LOGROTATE="${RSPAMD_LOGROTATE:-true}"
RSPAMD_LOGROTATE_CONF="${RSPAMD_LOGROTATE_CONF:-/etc/rspamd/logrotate.conf}"
RSPAMD_LOGROTATE_INTERVAL="${RSPAMD_LOGROTATE_INTERVAL:-500}"

log() { echo "docker-entrypoint.sh: $*" >&2; }

if [ "$RSPAMD_LOG_TYPE" = "file" ]; then
    log_dir="$(dirname "$RSPAMD_LOG_FILE")"
    mkdir -p "$log_dir"

    # Ensure the file exists so `tail -F` and logrotate have something to open
    # straight away (rspamd will reopen/append to it once it starts).
    : > "$RSPAMD_LOG_FILE" 2>/dev/null || true

    if [ "$RSPAMD_LOG_TAIL" = "true" ]; then
        log "tailing $RSPAMD_LOG_FILE to stdout"
        tail -n0 -F "$RSPAMD_LOG_FILE" &
    fi

    if [ "$RSPAMD_LOGROTATE" = "true" ] && [ -f "$RSPAMD_LOGROTATE_CONF" ]; then
        # state file in the writable log dir (the default /var/lib/logrotate is
        # not writable as UID 11333).
        rotate_state="${log_dir}/logrotate.status"

        log "logrotate every ${RSPAMD_LOGROTATE_INTERVAL}s (config ${RSPAMD_LOGROTATE_CONF})"
        # If this loop dies the worst case is the log grows until pod restart
        while sleep "$RSPAMD_LOGROTATE_INTERVAL"; do
            logrotate -s "$rotate_state" "$RSPAMD_LOGROTATE_CONF" || \
                log "logrotate run failed (continuing)"
        done &
    elif [ "$RSPAMD_LOGROTATE" = "true" ]; then
        log "logrotate enabled but no config at ${RSPAMD_LOGROTATE_CONF}; skipping rotation"
    fi
fi

# exec so rspamd becomes PID 1 and is the target of SIGUSR1 / SIGTERM.
exec "$@"
