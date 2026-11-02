FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml tsconfig.base.json ./
COPY apps/control-plane ./apps/control-plane
RUN pnpm install --frozen-lockfile && pnpm --filter @poc/control-plane build && pnpm --filter @poc/control-plane deploy --prod --legacy /opt/control

FROM node:22-bookworm-slim
RUN useradd --create-home --uid 10001 poc
WORKDIR /app
COPY --from=build /app/apps/control-plane/dist ./dist
COPY --from=build /opt/control/node_modules ./node_modules
COPY --from=build /app/apps/control-plane/package.json ./package.json
COPY apps/control-plane/assets/kubectl-ate /usr/local/bin/kubectl-ate
COPY apps/control-plane/entrypoint.sh /usr/local/bin/poc-entrypoint
COPY infra/local/egress-policy.yaml /app/config/egress-policy.yaml
RUN chmod 755 /usr/local/bin/kubectl-ate /usr/local/bin/poc-entrypoint && mkdir /data && chown poc:poc /data
USER poc
ENV POC_HOST=0.0.0.0 POC_PORT=8080 POC_DB_PATH=/data/poc.sqlite POC_SUBSTRATE_MODE=real POC_EGRESS_POLICY_PATH=/app/config/egress-policy.yaml
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/poc-entrypoint"]
