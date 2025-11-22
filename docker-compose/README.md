# Docker compose self hosting

**Caddy routes**

```sh
http://localhost/api    → Backend
http://localhost/auth   → Backend
http://localhost/admin  → Backend
http://localhost/v2/    → Backend - for registry proxy
http://localhost        → Dashboard
ws://localhost/ws       → Centrifugo
```