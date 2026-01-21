#!/bin/bash

################################################################################
# Physio AI - Automatisches Installations-Script
#
# Dieses Script richtet die Physio AI Applikation automatisch ein:
# - Generiert sichere Passwörter und Secrets
# - Erstellt die .env-Datei aus dem Template
# - Startet die Docker-Container
# - Erstellt den ersten Admin-User
#
# Verwendung:
#   chmod +x install.sh
#   ./install.sh
################################################################################

set -e  # Bei Fehler abbrechen

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              🏥 Physio AI - Installation                     ║"
echo "║                                                              ║"
echo "║  Personalplanung & Kapazitätsmanagement für Physiotherapie  ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Prüfe ob Docker installiert ist
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker ist nicht installiert!${NC}"
    echo ""
    echo "Bitte installiere Docker zuerst:"
    echo "  https://docs.docker.com/get-docker/"
    echo ""
    exit 1
fi

# Prüfe ob Docker Compose installiert ist
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose ist nicht installiert!${NC}"
    echo ""
    echo "Bitte installiere Docker Compose zuerst:"
    echo "  https://docs.docker.com/compose/install/"
    echo ""
    exit 1
fi

# Setze DOCKER_COMPOSE Command (docker-compose oder docker compose)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Prüfe ob openssl installiert ist
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}❌ openssl ist nicht installiert!${NC}"
    echo ""
    echo "Bitte installiere openssl zuerst:"
    echo "  Linux: apt-get install openssl oder yum install openssl"
    echo "  macOS: brew install openssl"
    echo ""
    exit 1
fi

echo -e "${BLUE}📋 Installations-Schritte:${NC}"
echo "  1. Konfiguration prüfen"
echo "  2. Sichere Passwörter generieren"
echo "  3. .env-Datei erstellen"
echo "  4. Docker-Container starten"
echo "  5. Datenbank initialisieren"
echo "  6. Admin-User erstellen"
echo ""

# Prüfe ob .env bereits existiert
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env-Datei existiert bereits!${NC}"
    echo ""
    read -p "Möchten Sie die bestehende .env-Datei überschreiben? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Installation abgebrochen.${NC}"
        exit 1
    fi
fi

# Prüfe ob Template existiert
if [ ! -f ".env.prod.example" ]; then
    echo -e "${RED}❌ .env.prod.example nicht gefunden!${NC}"
    echo "Bitte stelle sicher, dass du im Projektverzeichnis bist."
    exit 1
fi

echo ""
echo -e "${GREEN}✓${NC} Voraussetzungen erfüllt"
echo ""

# ========================================================================
# SCHRITT 1: Benutzer-Konfiguration
# ========================================================================

echo -e "${BLUE}📝 Schritt 1/6: Konfiguration${NC}"
echo ""

# Standard-Werte
DEFAULT_DOMAIN="localhost"
DEFAULT_BACKEND_PORT="8011"
DEFAULT_FRONTEND_PORT="3011"
DEFAULT_ADMIN_EMAIL="admin@physio-cockpit.local"

# Frage nach Domain
read -p "Domain (für Production, z.B. physio-cockpit.de) [$DEFAULT_DOMAIN]: " DOMAIN
DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

# Frage nach Ports (nur bei localhost relevant)
if [ "$DOMAIN" = "localhost" ] || [ "$DOMAIN" = "127.0.0.1" ]; then
    read -p "Backend Port [$DEFAULT_BACKEND_PORT]: " BACKEND_PORT
    BACKEND_PORT=${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}

    read -p "Frontend Port [$DEFAULT_FRONTEND_PORT]: " FRONTEND_PORT
    FRONTEND_PORT=${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}

    FRONTEND_URL="http://${DOMAIN}:${FRONTEND_PORT}"
    BACKEND_URL="http://${DOMAIN}:${BACKEND_PORT}"
    WEBAUTHN_RP_ID="localhost"
else
    BACKEND_PORT="8011"
    FRONTEND_PORT="3011"
    FRONTEND_URL="https://${DOMAIN}"
    BACKEND_URL="https://api.${DOMAIN}"
    WEBAUTHN_RP_ID="${DOMAIN}"
fi

# Frage nach Admin-Email
read -p "Admin E-Mail [$DEFAULT_ADMIN_EMAIL]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}

echo ""
echo -e "${GREEN}✓${NC} Konfiguration abgeschlossen"
echo ""

# ========================================================================
# SCHRITT 2: Passwörter & Secrets generieren
# ========================================================================

echo -e "${BLUE}🔐 Schritt 2/6: Sichere Passwörter generieren${NC}"
echo ""

# Generiere sichere Passwörter
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
SECRET_KEY=$(openssl rand -base64 64 | tr -d "\n")

echo -e "${GREEN}✓${NC} Passwörter generiert"
echo ""

# ========================================================================
# SCHRITT 3: .env-Datei erstellen
# ========================================================================

echo -e "${BLUE}📄 Schritt 3/6: .env-Datei erstellen${NC}"
echo ""

# Kopiere Template
cp .env.prod.example .env

# Ersetze Platzhalter in .env
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed syntax
    sed -i '' "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
    sed -i '' "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
    sed -i '' "s|FRONTEND_URL=.*|FRONTEND_URL=${FRONTEND_URL}|g" .env
    sed -i '' "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${BACKEND_URL}|g" .env
    sed -i '' "s|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${FRONTEND_URL}|g" .env
    sed -i '' "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${ADMIN_EMAIL}|g" .env
    sed -i '' "s|WEBAUTHN_RP_ID=.*|WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID}|g" .env
    sed -i '' "s|BACKEND_PORT=.*|BACKEND_PORT=${BACKEND_PORT}|g" .env
    sed -i '' "s|FRONTEND_PORT=.*|FRONTEND_PORT=${FRONTEND_PORT}|g" .env
else
    # Linux sed syntax
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
    sed -i "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
    sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=${FRONTEND_URL}|g" .env
    sed -i "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${BACKEND_URL}|g" .env
    sed -i "s|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${FRONTEND_URL}|g" .env
    sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${ADMIN_EMAIL}|g" .env
    sed -i "s|WEBAUTHN_RP_ID=.*|WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID}|g" .env
    sed -i "s|BACKEND_PORT=.*|BACKEND_PORT=${BACKEND_PORT}|g" .env
    sed -i "s|FRONTEND_PORT=.*|FRONTEND_PORT=${FRONTEND_PORT}|g" .env
fi

echo -e "${GREEN}✓${NC} .env-Datei erstellt"
echo ""

# ========================================================================
# SCHRITT 4: Docker-Container starten
# ========================================================================

echo -e "${BLUE}🐳 Schritt 4/6: Docker-Container starten${NC}"
echo ""

# Stoppe alte Container falls vorhanden
echo "Stoppe alte Container (falls vorhanden)..."
$DOCKER_COMPOSE -f docker-compose.prod.yml down 2>/dev/null || true

# Baue und starte Container
echo "Baue Docker Images (das kann einige Minuten dauern)..."
$DOCKER_COMPOSE -f docker-compose.prod.yml build --no-cache

echo "Starte Container..."
$DOCKER_COMPOSE -f docker-compose.prod.yml up -d

echo ""
echo -e "${GREEN}✓${NC} Container gestartet"
echo ""

# Warte auf Datenbank
echo "Warte auf Datenbank-Start (max. 30 Sekunden)..."
for i in {1..30}; do
    if $DOCKER_COMPOSE -f docker-compose.prod.yml exec -T db pg_isready -U postgres > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Datenbank ist bereit"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# ========================================================================
# SCHRITT 5: Datenbank initialisieren
# ========================================================================

echo ""
echo -e "${BLUE}🗄️  Schritt 5/6: Datenbank initialisieren${NC}"
echo ""

# Führe Alembic Migrationen aus
echo "Führe Datenbank-Migrationen aus..."
$DOCKER_COMPOSE -f docker-compose.prod.yml exec -T backend alembic upgrade head

echo -e "${GREEN}✓${NC} Datenbank initialisiert"
echo ""

# ========================================================================
# SCHRITT 6: Admin-User erstellen
# ========================================================================

echo ""
echo -e "${BLUE}👤 Schritt 6/6: Admin-User erstellen${NC}"
echo ""

# Generiere Admin-Passwort
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Erstelle Admin-User
echo "Erstelle Admin-Benutzer..."
$DOCKER_COMPOSE -f docker-compose.prod.yml exec -T backend python create_admin.py \
    --username admin \
    --email "${ADMIN_EMAIL}" \
    --password "${ADMIN_PASSWORD}" 2>&1 | grep -v "UserWarning" || true

echo -e "${GREEN}✓${NC} Admin-User erstellt"
echo ""

# ========================================================================
# FERTIG!
# ========================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              ✅ Installation erfolgreich!                    ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}📝 Zugangsdaten:${NC}"
echo ""
echo "  Frontend:  ${FRONTEND_URL}"
echo "  Backend:   ${BACKEND_URL}"
echo ""
echo "  Admin-Benutzername: admin"
echo "  Admin-Passwort:     ${ADMIN_PASSWORD}"
echo "  Admin-Email:        ${ADMIN_EMAIL}"
echo ""
echo -e "${YELLOW}⚠️  WICHTIG: Speichern Sie diese Zugangsdaten sicher!${NC}"
echo ""
echo -e "${BLUE}📚 Nächste Schritte:${NC}"
echo ""
echo "  1. Öffne ${FRONTEND_URL} in deinem Browser"
echo "  2. Melde dich mit den obigen Zugangsdaten an"
echo "  3. Ändere dein Passwort im User-Profil"
echo "  4. Konfiguriere SMTP für E-Mails (optional)"
echo ""
echo -e "${BLUE}🔧 Nützliche Befehle:${NC}"
echo ""
echo "  Container-Status anzeigen:"
echo "    ${DOCKER_COMPOSE} -f docker-compose.prod.yml ps"
echo ""
echo "  Logs anzeigen:"
echo "    ${DOCKER_COMPOSE} -f docker-compose.prod.yml logs -f"
echo ""
echo "  Container neustarten:"
echo "    ${DOCKER_COMPOSE} -f docker-compose.prod.yml restart"
echo ""
echo "  Container stoppen:"
echo "    ${DOCKER_COMPOSE} -f docker-compose.prod.yml down"
echo ""
echo "  Backup erstellen:"
echo "    docker exec physio_db pg_dump -U postgres Planing > backup_\$(date +%Y%m%d).sql"
echo ""
echo -e "${GREEN}Viel Erfolg mit Physio AI! 🚀${NC}"
echo ""

# Speichere Zugangsdaten in Datei
cat > INSTALLATION_INFO.txt <<EOF
╔══════════════════════════════════════════════════════════════╗
║              🏥 Physio AI - Installation                     ║
╚══════════════════════════════════════════════════════════════╝

Installation abgeschlossen am: $(date)

Zugangsdaten:
-------------
Frontend:  ${FRONTEND_URL}
Backend:   ${BACKEND_URL}

Admin-Benutzername: admin
Admin-Passwort:     ${ADMIN_PASSWORD}
Admin-Email:        ${ADMIN_EMAIL}

Datenbank-Passwort: ${DB_PASSWORD}

⚠️  WICHTIG: Diese Datei enthält sensible Zugangsdaten!
    Bitte sicher aufbewahren und NICHT in Git committen!

Nächste Schritte:
-----------------
1. Öffne ${FRONTEND_URL} in deinem Browser
2. Melde dich mit den obigen Zugangsdaten an
3. Ändere dein Passwort im User-Profil
4. Konfiguriere SMTP für E-Mails (optional, siehe .env)

Container-Verwaltung:
---------------------
Status:     ${DOCKER_COMPOSE} -f docker-compose.prod.yml ps
Logs:       ${DOCKER_COMPOSE} -f docker-compose.prod.yml logs -f
Restart:    ${DOCKER_COMPOSE} -f docker-compose.prod.yml restart
Stoppen:    ${DOCKER_COMPOSE} -f docker-compose.prod.yml down

Backup:     docker exec physio_db pg_dump -U postgres Planing > backup_\$(date +%Y%m%d).sql
EOF

echo -e "${GREEN}📄 Zugangsdaten wurden in INSTALLATION_INFO.txt gespeichert${NC}"
echo ""
