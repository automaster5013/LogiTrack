#!/bin/bash
set -euo pipefail
dnf install -y docker git jq
install -d -m 0755 /usr/local/libexec/docker/cli-plugins
curl --fail --location --retry 5 --proto '=https' --tlsv1.2 \
  https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-linux-x86_64 \
  --output /usr/local/libexec/docker/cli-plugins/docker-compose
echo 'db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576  /usr/local/libexec/docker/cli-plugins/docker-compose' | sha256sum --check
chmod 0755 /usr/local/libexec/docker/cli-plugins/docker-compose
docker compose version
systemctl enable --now docker
install -d -m 0750 -o root -g root /opt/logitrack/releases
install -d -m 0700 -o root -g root /opt/logitrack/secrets
cat >/etc/systemd/system/logitrack.service <<'UNIT'
[Unit]
Description=LogiTrack staging Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/logitrack/current
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=900
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
