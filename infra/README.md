# Substrate fijado para la PoC

La versión upstream es el commit exacto de `substrate.lock`. Los scripts locales lo obtienen en `infra/.cache/substrate`, verifican el SHA antes de ejecutar comandos y usan el [quickstart oficial de ese commit](https://github.com/agent-substrate/substrate/tree/0f7ebfa3061cc37f6897ec40a130660994259631#quickstart-development).

Prerequisitos locales: Node.js 22+, pnpm, Go, kubectl, Docker daemon activo y memoria suficiente para kind. La instalación no usa AWS. Ejecutar `infra/local/up.sh`, `infra/local/install-substrate.sh`, `infra/local/smoke-substrate.sh` y `infra/local/down.sh`. En AWS, ningún script puede aplicar Terraform hasta aprobar los gates locales y financieros.
