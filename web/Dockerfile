FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Local dev only (docker-compose.local.yml): source is bind-mounted over this,
# node_modules stays in the image layer via an anonymous volume.
FROM deps AS dev
EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--host"]

# Base for `web-generate` (docker-compose.yml) -- `nuxt generate` runs at
# container runtime, not image build time, since it needs to reach the live
# PostgREST over the compose network.
FROM deps AS build
WORKDIR /app
COPY . .

# Static file server for the prod site -- content comes from the `web_static`
# volume `web-generate` writes to, not from this image.
FROM caddy:2-alpine AS run
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 3000
