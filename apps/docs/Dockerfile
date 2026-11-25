# Wain's docs, deployed by the infra repo's deploy-wain.sh as wain-docs. wainhq.com
# serves them at /docs through a rewrite to this app (DOCS_ORIGIN). Blume writes every
# link with /docs in front but the files at the output root, so /docs/x there is /x here.
# Built from the repository root for the pnpm workspace.
FROM node:22-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY . .
RUN pnpm install --frozen-lockfile --filter @wain/docs
WORKDIR /repo/apps/docs
RUN pnpm build

FROM nginx:1.29-alpine
COPY apps/docs/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/apps/docs/dist /usr/share/nginx/html
EXPOSE 80
