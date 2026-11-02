FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml tsconfig.base.json ./
COPY apps/codex-actor ./apps/codex-actor
RUN pnpm install --frozen-lockfile && pnpm --filter @poc/codex-actor build && pnpm --filter @poc/codex-actor deploy --prod --legacy /opt/actor

FROM node:22-bookworm-slim
RUN npm install -g @openai/codex@0.166.0 && useradd --create-home --uid 10001 actor
WORKDIR /app/apps/codex-actor
COPY --from=build /app/apps/codex-actor/dist ./dist
COPY --from=build /app/apps/codex-actor/config ./config
COPY --from=build /opt/actor/node_modules ./node_modules
COPY --from=build /app/apps/codex-actor/package.json ./package.json
USER actor
ENV ACTOR_HOST=0.0.0.0
ENV CODEX_HOME=/home/actor/.codex
ENV CODEX_THREAD_STATE_PATH=/home/actor/thread.json
EXPOSE 8090
CMD ["node", "dist/server.js"]
