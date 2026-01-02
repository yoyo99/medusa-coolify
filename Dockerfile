# ============================================
# Stage 1: Builder (Installation + Build)
# ============================================
FROM node:20-alpine AS builder

# Variables d'environnement pour le build
ARG DATABASE_URL
ARG REDIS_URL
ARG WORKER_MODE=server
ARG PORT=9000

ENV DATABASE_URL=${DATABASE_URL}
ENV REDIS_URL=${REDIS_URL}
ENV WORKER_MODE=${WORKER_MODE}
ENV PORT=${PORT}
ENV NODE_ENV=production

WORKDIR /app

# Copie les fichiers de dépendances
COPY package.json yarn.lock ./

# Installation des dépendances (avec cache optimisé)
RUN yarn install --frozen-lockfile --production=false

# Copie tout le code source
COPY . .

# Build du projet (compilation TypeScript + Admin Dashboard)
RUN yarn build

# ============================================
# Stage 2: Runner (Production)
# ============================================
FROM node:20-alpine AS runner

# Variables d'environnement pour le runtime
ENV NODE_ENV=production
ENV PORT=9000

WORKDIR /app

# Copie les fichiers nécessaires depuis le builder
COPY --from=builder /app/package.json ./
COPY --from=builder /app/yarn.lock ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/medusa-config.ts ./
COPY --from=builder /app/migrations.sh ./

# Rend le script de migrations exécutable
RUN chmod +x ./migrations.sh

# Expose le port
EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=10 \
  CMD node -e "require('http').get('http://localhost:9000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }).on('error', () => process.exit(1));"

# Commande de démarrage
CMD ["sh", "-c", "./migrations.sh && yarn start"]
