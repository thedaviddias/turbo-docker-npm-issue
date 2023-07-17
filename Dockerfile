# To be run in the root of the turbo monorepo

FROM dockerhub.es.ecg.tools/node:16.14.0-slim AS base

## Disable husky
ENV HUSKY=0

RUN apt-get update && \
  apt-get install python3 -y && \
  apt-get install make -y && \
  apt-get install g++ -y

# ? -------------------------

FROM base AS builder
WORKDIR /app
COPY . .
RUN npx turbo prune --scope=web --docker

# This will create the out folder only with the nwa project
# used in the next step

# ? -------------------------

FROM base AS installer

WORKDIR /app

# First install the dependencies (as they change less often)
COPY .gitignore .gitignore
COPY --from=builder /app/out/json/ .
COPY --from=builder /app/out/package-lock.json ./package-lock.json
RUN npm install

# Build the project
COPY --from=builder /app/out/full/ .
# TODO: Remove this copy once https://github.com/vercel/turbo/issues/3758 is fixed
# See this issue comment: https://github.com/vercel/turbo/issues/3758#issuecomment-1634672382
COPY ./turbo.json .
RUN npx turbo run build --filter=web...

# ? -------------------------

FROM base AS runner

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Don't run production as root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
USER nextjs

COPY --from=installer /app/apps/web/next.config.js .
COPY --from=installer /app/apps/web/package.json .

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/.next/standalone ./
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/public ./apps/web/public

EXPOSE 3000

ENV PORT 3000

CMD ["node", "apps/nwa/server.js"]
