#!/bin/bash
set -euo pipefail

# Logging destination. "console" (the default) leaves rspamd's upstream
# behaviour untouched. "file" makes the entrypoint point rspamd at a log file
# (via override.d/logging.inc) and tail/rotate it.
RSPAMD_LOG_TYPE="${RSPAMD_LOG_TYPE:-console}"
RSPAMD_LOG_FILE="${RSPAMD_LOG_FILE:-/var/log/rspamd/rspamd.log}"

# Re-emit the log file to stdout (for alloy/Loki) when logging to a file.
RSPAMD_LOG_TAIL="${RSPAMD_LOG_TAIL:-true}"

# In-process log rotation.
RSPAMD_LOGROTATE="${RSPAMD_LOGROTATE:-true}"
RSPAMD_LOGROTATE_SIZE="${RSPAMD_LOGROTATE_SIZE:-100M}"
RSPAMD_LOGROTATE_KEEP="${RSPAMD_LOGROTATE_KEEP:-3}"
RSPAMD_LOGROTATE_INTERVAL="${RSPAMD_LOGROTATE_INTERVAL:-500}"

log() { echo "docker-entrypoint.sh: $*" >&2; }

if [ "$RSPAMD_LOG_TYPE" = "file" ]; then
    log_dir="$(dirname "$RSPAMD_LOG_FILE")"
    mkdir -p "$log_dir"

    # Ensure the file exists so `tail -F` and logrotate have something to open
    # straight away (rspamd will reopen/append to it once it starts).
    : > "$RSPAMD_LOG_FILE" 2>/dev/null || true

    # Point rspamd at the file. override.d strictly overrides the upstream
    # logging.inc; level/log_usec/debug_modules still come from local.d (the
    # chart's ConfigMap). The dir is chowned to this UID in the Dockerfile.
    cat > /etc/rspamd/override.d/logging.inc <<EOF
type = "file";
filename = "${RSPAMD_LOG_FILE}";
EOF
    log "rspamd logging to $RSPAMD_LOG_FILE (override.d/logging.inc)"

    if [ "$RSPAMD_LOG_TAIL" = "true" ]; then
        log "tailing $RSPAMD_LOG_FILE to stdout"
        tail -n0 -F "$RSPAMD_LOG_FILE" &
    fi

    if [ "$RSPAMD_LOGROTATE" = "true" ]; then
        # config + state live in the writable log dir (the default
        # /var/lib/logrotate is not writable as UID 11333).
        rotate_conf="${log_dir}/logrotate.conf"
        rotate_state="${log_dir}/logrotate.status"

        # postrotate sends USR1 to PID 1 (rspamd) so it reopens the log.
        cat > "$rotate_conf" <<EOF
${RSPAMD_LOG_FILE} {
    missingok
    notifempty
    size ${RSPAMD_LOGROTATE_SIZE}
    rotate ${RSPAMD_LOGROTATE_KEEP}
    compress
    delaycompress
    create 0644
    sharedscripts
    postrotate
        kill -USR1 1 2>/dev/null || true
    endscript
}
EOF

        log "logrotate every ${RSPAMD_LOGROTATE_INTERVAL}s (size ${RSPAMD_LOGROTATE_SIZE}, keep ${RSPAMD_LOGROTATE_KEEP})"
        # If this loop dies the worst case is the log grows until pod restart
        while sleep "$RSPAMD_LOGROTATE_INTERVAL"; do
            logrotate -s "$rotate_state" "$rotate_conf" || \
                log "logrotate run failed (continuing)"
        done &
    fi
fi

# exec so rspamd becomes PID 1 and is the target of SIGUSR1 / SIGTERM.
exec "$@"
