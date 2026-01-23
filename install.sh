#!/bin/bash
set -e

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              🏥 Physio AI - Installation                     ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Voraussetzungen prüfen
if ! command -v docker &> /dev/null; then echo -e "${RED}❌ Docker fehlt.${NC}"; exit 1; fi
if ! command -v openssl &> /dev/null; then echo -e "${RED}❌ openssl fehlt.${NC}"; exit 1; fi

# ========================================================================
# SCHRITT 1-3: Konfiguration & .env
# ========================================================================
echo -e "${BLUE}📝 Konfiguration...${NC}"

if [ ! -f ".env" ]; then
    if [ ! -f ".env.example" ]; then
        echo -e "${RED}❌ Keine .env.example gefunden!${NC}"
        exit 1
    fi

    echo ""
    echo -e "${YELLOW}Konfigurieren Sie Ihre Installation (Enter = Standardwert):${NC}"
    echo ""

    # Domain & Ports
    read -p "🌐 Domain [localhost]: " INPUT_DOMAIN
    DOMAIN="${INPUT_DOMAIN:-localhost}"

    read -p "🔌 Backend Port [8011]: " INPUT_BACKEND_PORT
    BACKEND_PORT="${INPUT_BACKEND_PORT:-8011}"

    read -p "🔌 Frontend Port [3011]: " INPUT_FRONTEND_PORT
    FRONTEND_PORT="${INPUT_FRONTEND_PORT:-3011}"

    # Admin
    read -p "📧 Admin E-Mail [admin@physio.ai]: " INPUT_ADMIN_EMAIL
    ADMIN_EMAIL="${INPUT_ADMIN_EMAIL:-admin@physio.ai}"

    # SMTP (optional)
    echo ""
    echo -e "${BLUE}📧 SMTP Konfiguration (optional, Enter = überspringen):${NC}"
    read -p "   SMTP Host [smtp.gmail.com]: " INPUT_SMTP_HOST
    SMTP_HOST="${INPUT_SMTP_HOST:-smtp.gmail.com}"

    read -p "   SMTP Port [587]: " INPUT_SMTP_PORT
    SMTP_PORT="${INPUT_SMTP_PORT:-587}"

    read -p "   SMTP User []: " SMTP_USER

    read -s -p "   SMTP Passwort []: " SMTP_PASS
    echo ""

    # KI (optional)
    echo ""
    echo -e "${BLUE}🤖 KI Konfiguration (optional):${NC}"
    read -p "   Ollama URL [http://host.docker.internal:11434](http://host.docker.internal:11434): " INPUT_OLLAMA_URL
    OLLAMA_BASE_URL="${INPUT_OLLAMA_URL:-http://host.docker.internal:11434}"

    read -p "   Ollama Model [llama3.1:8b]: " INPUT_OLLAMA_MODEL
    OLLAMA_MODEL="${INPUT_OLLAMA_MODEL:-llama3.1:8b}"

    read -p "   OpenRouter API Key []: " OPENROUTER_API_KEY

    # .env erstellen
    echo ""
    echo "Erstelle .env aus .env.example..."
    cp .env.example .env

    # Passwörter generieren
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    SECRET_KEY=$(openssl rand -base64 64 | tr -d "\n")

    # URLs berechnen
    if [[ "$DOMAIN" == "localhost" ]]; then
        FRONTEND_URL="http://${DOMAIN}:${FRONTEND_PORT}"
        BACKEND_URL="http://${DOMAIN}:${BACKEND_PORT}"
    else
        # Für echte Domains (mit HTTPS)
        FRONTEND_URL="https://${DOMAIN}"
        BACKEND_URL="https://${DOMAIN}/api"
    fi

    # Alle Werte ersetzen (Linux)
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
    sed -i "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
    sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=${FRONTEND_URL}|g" .env
    sed -i "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${BACKEND_URL}|g" .env
    sed -i "s|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${FRONTEND_URL}|g" .env
    sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${ADMIN_EMAIL}|g" .env
    sed -i "s|WEBAUTHN_RP_ID=.*|WEBAUTHN_RP_ID=${DOMAIN}|g" .env
    sed -i "s|BACKEND_PORT=.*|BACKEND_PORT=${BACKEND_PORT}|g" .env
    sed -i "s|FRONTEND_PORT=.*|FRONTEND_PORT=${FRONTEND_PORT}|g" .env

    # SMTP (nur wenn User gesetzt)
    sed -i "s|SMTP_HOST=.*|SMTP_HOST=${SMTP_HOST}|g" .env
    sed -i "s|SMTP_PORT=.*|SMTP_PORT=${SMTP_PORT}|g" .env
    [[ -n "$SMTP_USER" ]] && sed -i "s|SMTP_USER=.*|SMTP_USER=${SMTP_USER}|g" .env
    [[ -n "$SMTP_PASS" ]] && sed -i "s|SMTP_PASS=.*|SMTP_PASS=${SMTP_PASS}|g" .env

    # KI
    sed -i "s|OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=${OLLAMA_BASE_URL}|g" .env
    sed -i "s|OLLAMA_MODEL=.*|OLLAMA_MODEL=${OLLAMA_MODEL}|g" .env
    [[ -n "$OPENROUTER_API_KEY" ]] && sed -i "s|OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=${OPENROUTER_API_KEY}|g" .env

    echo -e "${GREEN}✓ .env Datei erstellt mit Ihren Einstellungen.${NC}"
else
    echo -e "${YELLOW}ℹ️  .env existiert bereits. Überspringe Konfiguration.${NC}"
fi


# ========================================================================
# SCHRITT 4: Container starten
# ========================================================================
echo -e "${BLUE}🐳 Starte Container...${NC}"
# Orphans entfernen um Konflikte zu vermeiden
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

# ========================================================================
# SCHRITT 5: DB Check & Migrationen
# ========================================================================
echo "⏳ Warte auf Datenbank..."
counter=0
until docker compose exec backend python3 -c "from database import engine; engine.connect()" 2>/dev/null; do
    sleep 2
    counter=$((counter+1))
    echo -n "."
    if [ $counter -gt 30 ]; then echo -e "\n${RED}❌ Timeout DB.${NC}"; exit 1; fi
done
echo -e "\n${GREEN}✅ Datenbank bereit.${NC}"

echo "🔧 Migrationen..."
docker compose exec backend alembic upgrade head || true

# ========================================================================
# SCHRITT 6: SCHEMA REPARATUR (WICHTIG!)
# ========================================================================
# Damit wir KEINEN Employee für den Admin brauchen (sonst gehen Demo-Daten nicht!)
echo -e "${BLUE}🛠️ Repariere Datenbankschema (Audit Log Fix)...${NC}"
docker compose exec -T db psql -U postgres -d Planing -c "
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'audit_logs_user_id_fkey') THEN
        ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_user_id_fkey;
    END IF;
    -- Verknüpfung auf USERS (nicht Employees) ändern
    ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END \$\$;
"

# ========================================================================
# SCHRITT 7: Admin User erstellen
# ========================================================================
echo -e "${BLUE}👤 Erstelle Admin User...${NC}"

ADMIN_USER="admin"
ADMIN_EMAIL=$(grep ADMIN_EMAIL .env | cut -d '=' -f2 || echo "admin@physio.ai")
ADMIN_PASS="admin123"

docker compose exec -T backend python3 - <<EOF
import sys
import bcrypt
from sqlalchemy import text
from database import SessionLocal

username = "${ADMIN_USER}"
email = "${ADMIN_EMAIL}".strip()
password = "${ADMIN_PASS}"
salt = bcrypt.gensalt()
hashed = bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

db = SessionLocal()
try:
    # Wir erstellen NUR den User. Da der Schema-Fix oben lief, 
    # brauchen wir KEINEN Employee-Eintrag mehr für den Login/Audit-Log.
    stmt = text("""
        INSERT INTO users (username, email, hashed_password, is_admin, is_active, role)
        VALUES (:u, :e, :p, true, true, 'admin')
        ON CONFLICT (username) DO UPDATE 
        SET hashed_password = :p, is_admin = true, is_active = true, role = 'admin'
    """)
    db.execute(stmt, {"u": username, "e": email, "p": hashed})
    db.commit()
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
finally:
    db.close()
EOF

# ========================================================================
# SCHRITT 8: Demo Daten (create_demo_data.py)
# ========================================================================
echo ""
echo -e "${BLUE}🌱 Demo-Daten${NC}"
echo "Möchten Sie Demo-Daten laden? (Patienten, Teams, Termine...)"
read -p "Demo-Daten laden? (j/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[JjYy]$ ]]; then
    # Hier nutzen wir den korrekten Namen und setzen die Variable auf TRUE
    if docker compose exec -T backend test -f create_demo_data.py; then
        echo "Lade Demo-Daten (create_demo_data.py)..."
        # Environment Variable setzen UND Script ausführen
        docker compose exec -e INIT_DEMO_DATA=true -T backend python3 create_demo_data.py
        
        echo -e "${GREEN}✓ Demo-Daten Script ausgeführt.${NC}"
    else
        echo -e "${RED}❌ Konnte 'create_demo_data.py' nicht finden!${NC}"
    fi
else
    echo "Überspringe Demo-Daten. System ist leer."
fi

# ========================================================================
# FERTIG
# ========================================================================
echo ""
echo -e "${GREEN}✅ Installation fertig!${NC}"
echo "---------------------------------------------------"
echo -e "🌍 URL:       $(grep FRONTEND_URL .env | cut -d '=' -f2 || echo 'http://localhost:3011')"
echo -e "👤 User:      ${ADMIN_USER}"
echo -e "🔑 Pass:      ${ADMIN_PASS}"
echo "---------------------------------------------------"
