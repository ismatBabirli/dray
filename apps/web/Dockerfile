# Wain's site and account server, deployed by the infra repo's deploy-wain.sh.
# Built from the repository root: pnpm needs the workspace, and the changelog page
# reads ../desktop/CHANGELOG.md. The root .dockerignore lets in only what this needs.
FROM node:22-alpine
RUN corepack enable
WORKDIR /repo
COPY . .
RUN pnpm install --frozen-lockfile --filter @wain/web

# Inlined into the pages by next build; Coolify passes it as --build-arg.
ARG NEXT_PUBLIC_SITE_URL
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL NEXT_TELEMETRY_DISABLED=1
WORKDIR /repo/apps/web
RUN pnpm build

ENV NODE_ENV=production PORT=3000
EXPOSE 3000
# Better Auth's tables first, so a new auth plugin's tables land on deploy.
CMD ["sh", "-c", "pnpm db:migrate && exec pnpm start"]
