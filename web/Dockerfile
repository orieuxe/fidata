FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Local dev only (docker-compose.local.yml): source is bind-mounted over this,
# node_modules stays in the image layer via an anonymous volume.
FROM deps AS dev
EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--host"]

FROM deps AS build
WORKDIR /app
COPY . .
RUN npm run build

FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/.output ./.output
EXPOSE 3000
CMD ["node", ".output/server/index.mjs"]
