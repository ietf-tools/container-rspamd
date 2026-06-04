ARG RSPAMD_VERSION
FROM rspamd/rspamd:${RSPAMD_VERSION}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends logrotate \
    && apt-get -q clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/*.log /var/log/dpkg.log

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER 11333:11333

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/rspamd", "-f"]
