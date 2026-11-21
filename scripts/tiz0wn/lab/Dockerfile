FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      xrdp xorgxrdp xfce4-session xfce4-panel xfce4-settings \
      xfce4-terminal dbus-x11 xauth xserver-xorg-core \
      ca-certificates procps passwd \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -aG ssl-cert xrdp
COPY entrypoint.sh /usr/local/bin/danstv-xrdp-entrypoint
# Windows Git may check shell scripts out as CRLF. A CRLF shebang makes
# the Linux kernel look for /bin/sh\\r and Docker exits with code 127.
# Convert inside the image as well, regardless of host checkout settings.
RUN sed -i 's/\r$//' /usr/local/bin/danstv-xrdp-entrypoint \
    && chmod 0755 /usr/local/bin/danstv-xrdp-entrypoint \
    && /bin/sh -n /usr/local/bin/danstv-xrdp-entrypoint
EXPOSE 3389/tcp
ENTRYPOINT ["/usr/local/bin/danstv-xrdp-entrypoint"]
