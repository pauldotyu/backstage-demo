# syntax=docker/dockerfile:1.7
#
# Multi-stage build for the Backstage backend (which also serves the frontend).
# Everything is built inside Docker; no host `yarn install` or `yarn build` is needed.
#
#   docker build -t backstage:local .
#
# Based on https://backstage.io/docs/deployment/docker#multi-stage-build

ARG NODE_IMAGE=node:24-trixie-slim

# Stage 1: a skeleton of the monorepo with only package.json files, so the
# dependency install layer is cached until a manifest or yarn.lock changes.
FROM ${NODE_IMAGE} AS packages

WORKDIR /app
COPY backstage.json package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages packages
COPY plugins plugins

RUN find packages plugins -mindepth 2 -maxdepth 2 \! -name "package.json" -exec rm -rf {} \+

# Stage 2: toolchain used to compile native modules (better-sqlite3, etc.).
FROM ${NODE_IMAGE} AS toolchain

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev

USER node
WORKDIR /app

# Stage 3: install all dependencies, type-check, and build the backend bundle.
FROM toolchain AS build

COPY --from=packages --chown=node:node /app .

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn install --immutable

COPY --chown=node:node . .

RUN yarn tsc
RUN yarn --cwd packages/backend build

RUN mkdir packages/backend/dist/skeleton packages/backend/dist/bundle \
    && tar xzf packages/backend/dist/skeleton.tar.gz -C packages/backend/dist/skeleton \
    && tar xzf packages/backend/dist/bundle.tar.gz -C packages/backend/dist/bundle

# Stage 4: production-only node_modules, compiled against the same base image.
FROM toolchain AS prod-deps

COPY --from=build --chown=node:node /app/.yarn ./.yarn
COPY --from=build --chown=node:node /app/.yarnrc.yml /app/backstage.json /app/yarn.lock /app/package.json ./
COPY --from=build --chown=node:node /app/packages/backend/dist/skeleton/ ./

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    NODE_ENV=production yarn workspaces focus --all --production

# Stage 5: runtime image. No compilers, runs as the unprivileged `node` user (uid 1000).
FROM ${NODE_IMAGE}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-0 tini

ENV NODE_ENV=production
# Required by the scaffolder's isolated-vm sandbox on Node 20+.
ENV NODE_OPTIONS="--no-node-snapshot"

WORKDIR /app

COPY --from=prod-deps --chown=node:node /app ./
COPY --from=build --chown=node:node /app/packages/backend/dist/bundle/ ./
COPY --chown=node:node app-config.yaml app-config.production.yaml ./

USER 1000:1000

EXPOSE 7007

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
