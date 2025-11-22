# Docker compose self hosting


**Installation**

```bash
curl https://raw.githubusercontent.com/usefloww/floww-self-hosting/refs/heads/main/docker-compose/install.sh -o install-floww.sh && bash install-floww.sh
```

**Caddy routes**

```sh
http://localhost/api    → Backend
http://localhost/auth   → Backend
http://localhost/admin  → Backend
http://localhost/v2/    → Backend - for registry proxy
http://localhost        → Dashboard
ws://localhost/ws       → Centrifugo
```