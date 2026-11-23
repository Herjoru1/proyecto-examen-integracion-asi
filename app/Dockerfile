FROM node:24-alpine
WORKDIR /srv/app
COPY --chown=node:node --chmod=0644 package*.json ./
RUN npm ci --omit=dev
COPY --chown=node:node --chmod=0644 server.js vistas.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
