# ===== STAGE 1: Dependencies =====
FROM node:20-alpine AS deps
WORKDIR /app

# Installer les outils système nécessaires
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    curl

# Copier les fichiers de dépendances
COPY package*.json ./

# Installer avec npm (pas yarn, pour éviter les conflits)
RUN npm ci --only=production && \
    npm cache clean --force

# ===== STAGE 2: Build =====
FROM node:20-alpine AS builder
WORKDIR /app

RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copier node_modules depuis deps
COPY --from=deps /app/node_modules ./node_modules

# Copier tout le code source
COPY . .

# Build Medusa (compile TypeScript + Admin)
RUN npm run build

# ===== STAGE 3: Production =====
FROM node:20-alpine AS runner
WORKDIR /app

# Installer curl pour healthcheck
RUN apk add --no-cache curl

# Créer un utilisateur non-root
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copier les fichiers buildés
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/medusa-config.js ./medusa-config.js
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./package.json

# Variables d'environnement
ENV NODE_ENV=production \
    PORT=9000

EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# Passer à l'utilisateur non-root
USER nodejs

# Démarrage avec migrations
CMD ["sh", "-c", "\
    echo '🔍 Waiting for database...' && \
    sleep 5 && \
    echo '🚀 Running migrations...' && \
    npx medusa migrations run && \
    echo \"🎯 Starting Medusa in ${WORKER_MODE:-server} mode\" && \
    if [ \"$WORKER_MODE\" = 'worker' ]; then \
        npx medusa start --worker; \
    else \
        npx medusa start; \
    fi"]
