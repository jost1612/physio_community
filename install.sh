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

# Standard-Werte
DEFAULT_DOMAIN="localhost"
DEFAULT_BACKEND_PORT="8011"
DEFAULT_FRONTEND_PORT="3011"
DEFAULT_ADMIN_EMAIL="admin@physio.ai"

if [ ! -f ".env" ]; then
    if [ ! -f ".env.example" ]; then
        echo -e "${RED}❌ Keine .env.example gefunden!${NC}"
        exit 1
    fi
    echo "Erstelle .env aus .env.example..."
    cp .env.example .env

    # Passwörter generieren
    echo "Generiere sichere Passwörter..."
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    SECRET_KEY=$(openssl rand -base64 64 | tr -d "\n")

    # URLs setzen
    FRONTEND_URL="http://${DEFAULT_DOMAIN}:${DEFAULT_FRONTEND_PORT}"
    BACKEND_URL="http://${DEFAULT_DOMAIN}:${DEFAULT_BACKEND_PORT}"
    WEBAUTHN_RP_ID="${DEFAULT_DOMAIN}"
    
    # Ersetzen in der .env Datei
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
        sed -i '' "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
        sed -i '' "s|FRONTEND_URL=.*|FRONTEND_URL=${FRONTEND_URL}|g" .env
        sed -i '' "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${BACKEND_URL}|g" .env
        sed -i '' "s|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${FRONTEND_URL}|g" .env
        sed -i '' "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${DEFAULT_ADMIN_EMAIL}|g" .env
        sed -i '' "s|WEBAUTHN_RP_ID=.*|WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID}|g" .env
        sed -i '' "s|BACKEND_PORT=.*|BACKEND_PORT=${DEFAULT_BACKEND_PORT}|g" .env
        sed -i '' "s|FRONTEND_PORT=.*|FRONTEND_PORT=${DEFAULT_FRONTEND_PORT}|g" .env
    else
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
        sed -i "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
        sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=${FRONTEND_URL}|g" .env
        sed -i "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${BACKEND_URL}|g" .env
        sed -i "s|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${FRONTEND_URL}|g" .env
        sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${DEFAULT_ADMIN_EMAIL}|g" .env
        sed -i "s|WEBAUTHN_RP_ID=.*|WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID}|g" .env
        sed -i "s|BACKEND_PORT=.*|BACKEND_PORT=${DEFAULT_BACKEND_PORT}|g" .env
        sed -i "s|FRONTEND_PORT=.*|FRONTEND_PORT=${DEFAULT_FRONTEND_PORT}|g" .env
    fi
    echo -e "${GREEN}✓ .env Datei erstellt.${NC}"
else
    echo -e "${YELLOW}ℹ️  .env existiert bereits.${NC}"
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
