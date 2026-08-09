# syntax=docker/dockerfile:1.7

# Multi-stage build for Next.js 16 (standalone output) on Node.js 22 (Alpine).
#
# NOTE: build context is the REPOSITORY ROOT (storefront depends on local packages
# via file:../platform/packages/*), so paths below are written against that layout:
#   docker build -f storefront/Dockerfile \
#     --build-arg PALLASTRADE_API_URL=https://your-pallastrade.example.com \
#     --build-arg PALLASTRADE_PUBLISHABLE_KEY=your_publishable_key .
#
# Build (PallasTrade env required: pages are prerendered against the PallasTrade API at build time):
#   --build-arg PALLASTRADE_API_URL=https://your-pallastrade.example.com
#   --build-arg PALLASTRADE_PUBLISHABLE_KEY=your_publishable_key
#
# Run:
#   docker run -p 3001:3001 --env-file .env.local storefront

ARG NODE_VERSION=22-alpine


# ---- deps: install production+dev dependencies for the build ----
FROM node:${NODE_VERSION} AS deps
WORKDIR /app

# Optional CN mirrors (empty = official). APK_MIRROR e.g. mirrors.aliyun.com;
# NPM_REGISTRY e.g. https://registry.npmmirror.com
ARG APK_MIRROR=""
ARG NPM_REGISTRY=""

# libc6-compat keeps a few native modules happy on Alpine (musl).
RUN if [ -n "$APK_MIRROR" ]; then \
      sed -i "s|dl-cdn.alpinelinux.org|$APK_MIRROR|g" /etc/apk/repositories; \
    fi && \
    apk add --no-cache libc6-compat && corepack enable

# Copy storefront manifests + local file: dependencies (../platform/packages/*)
COPY storefront/package.json storefront/pnpm-lock.yaml storefront/pnpm-workspace.yaml ./
COPY platform/packages/sdk ../platform/packages/sdk
COPY platform/packages/sdk-core ../platform/packages/sdk-core
COPY platform/packages/cli ../platform/packages/cli

RUN if [ -n "$NPM_REGISTRY" ]; then pnpm config set registry "$NPM_REGISTRY"; fi

RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# pnpm pack excludes dist/ (gitignored) when packing file: deps, so copy the
# real sdk dist (incl. subpaths like ./webhooks) into pnpm's sdk copy.
RUN cp -r /platform/packages/sdk/dist /app/node_modules/@pallastrade/sdk/dist


# ---- builder: compile the Next.js app ----
FROM node:${NODE_VERSION} AS builder
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@11.1.1 --activate
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# PallasTrade API config — required at build time because the app prerenders pages
# that fetch from PallasTrade (categories, products, etc.).
ARG PALLASTRADE_API_URL
ARG PALLASTRADE_PUBLISHABLE_KEY
ENV PALLASTRADE_API_URL=$PALLASTRADE_API_URL \
    PALLASTRADE_PUBLISHABLE_KEY=$PALLASTRADE_PUBLISHABLE_KEY

# Optional Sentry release/source-map upload. When SENTRY_DSN is empty,
# next.config.ts skips withSentryConfig entirely, so the build still works.
# SENTRY_AUTH_TOKEN is intentionally not declared as ARG/ENV — it's mounted
# only for the build step via --mount=type=secret below, so it never persists
# in image layers or build cache.
ARG SENTRY_DSN=""
ARG SENTRY_ORG=""
ARG SENTRY_PROJECT=""
ENV SENTRY_DSN=$SENTRY_DSN \
    SENTRY_ORG=$SENTRY_ORG \
    SENTRY_PROJECT=$SENTRY_PROJECT

COPY --from=deps /app/node_modules ./node_modules
# Keep file:/workspace:* symlink targets alive (pnpm links ../platform/packages/* into node_modules).
COPY platform/packages/sdk ../platform/packages/sdk
COPY platform/packages/sdk-core ../platform/packages/sdk-core
COPY platform/packages/cli ../platform/packages/cli
COPY storefront/ ./

RUN --mount=type=secret,id=sentry_auth_token,required=false \
    SENTRY_AUTH_TOKEN="$(cat /run/secrets/sentry_auth_token 2>/dev/null || true)" \
    pnpm run build


# ---- runner: minimal runtime image ----
FROM node:${NODE_VERSION} AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3001
ENV HOSTNAME=0.0.0.0

# Runtime also needs the PallasTrade client config (server components read it).
ARG PALLASTRADE_API_URL
ARG PALLASTRADE_PUBLISHABLE_KEY
ENV PALLASTRADE_API_URL=$PALLASTRADE_API_URL \
    PALLASTRADE_PUBLISHABLE_KEY=$PALLASTRADE_PUBLISHABLE_KEY

RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

# Static assets and the standalone server bundle.
# The standalone output ships its own minimal node_modules.
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3001

CMD ["node", "server.js"]
