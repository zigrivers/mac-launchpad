# syntax=docker/dockerfile:1
# Multi-stage build for a Node app — small, correct, non-root.
# Lint it with:  hadolint Dockerfile     Inspect layers with:  dive <image>

# ---- deps: install node_modules (cached) ----
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# ---- build: compile / bundle ----
FROM node:24-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NODE_ENV=production
RUN npm run build

# ---- runtime: slim, non-root ----
FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000
# node:alpine ships an unprivileged `node` user (UID/GID 1000).
COPY --from=deps  --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist         ./dist
COPY --from=build --chown=node:node /app/package.json ./package.json
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]

# --- Next.js? Use standalone output instead of the runtime stage above ---
#   next.config.js:  output: 'standalone'
#   FROM node:24-alpine AS runtime
#   WORKDIR /app
#   ENV NODE_ENV=production PORT=3000 HOSTNAME="0.0.0.0"
#   COPY --from=build --chown=node:node /app/public           ./public
#   COPY --from=build --chown=node:node /app/.next/standalone  ./
#   COPY --from=build --chown=node:node /app/.next/static      ./.next/static
#   USER node
#   EXPOSE 3000
#   CMD ["node", "server.js"]
# (standalone bundles its own server.js + traced deps — no node_modules copy.)
