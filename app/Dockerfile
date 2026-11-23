FROM node:24-alpine
WORKDIR /srv/app
COPY package*.json ./
RUN npm ci --omit=dev
COPY --chown=node:node server.js vistas.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
