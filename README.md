# 🏥 PhysioAI - Smart Shift Planning & Management

Willkommen bei PhysioAI. Dies ist das Deployment-Repository für die selbstgehostete Version unserer Praxis-Management-Software.

**PhysioAI** ist eine moderne Webanwendung zur Schichtplanung, Mitarbeiterverwaltung und Kapazitätsanalyse für Physiotherapie-Praxen, unterstützt durch lokale KI.

---

## ✨ Features

- **Intelligente Schichtplanung**: Automatisierte Planung basierend auf Verfügbarkeiten und Skills
- **Mitarbeiter-Verwaltung**: Stammdaten, Urlaubsverwaltung und Rollen-Management
- **KI-Assistent**: Integrierter KI-Support für Analysen und Planungsvorschläge (via Ollama)
- **Auswertungen**: Detaillierte Statistiken zu Produktivität und Auslastung
- **Audit-Logs**: Nachvollziehbare Änderungshistorie für alle wichtigen Daten
- **Responsive Design**: Funktioniert auf Desktop, Tablet und Mobile (PWA-fähig)

---

## 🚀 Voraussetzungen

### Software

- Docker (v20.10+)
- Docker Compose (v2.0+)
- *(Optional für KI-Funktionen):* Ollama installiert auf dem Host-System

### Hardware-Empfehlung

| Ressource | Minimum | Empfohlen (mit KI) |
|-----------|---------|-------------------|
| CPU | 2+ Cores | 4+ Cores |
| RAM | 4 GB | 8+ GB |
| Speicher | 10 GB frei | 10+ GB frei |

---

## 🛠️ Installation

Die Installation ist dank Docker und unserem Installations-Skript in wenigen Minuten erledigt.

### 1. Repository klonen

Laden Sie die Konfigurationsdateien herunter:

```bash
git clone https://github.com/DEIN-GITHUB-USER/physio-deploy.git
cd physio-deploy
```

### 2. Konfiguration & Setup

Wir haben ein Skript vorbereitet, das die Umgebungsvariablen einrichtet und sichere Passwörter generiert:

```bash
# Skript ausführbar machen
chmod +x install.sh

# Installation starten
./install.sh
```

Das Skript wird Sie durch folgende Schritte führen:

- Generierung sicherer Datenbank-Passwörter
- Erstellung eines kryptografisch sicheren `SECRET_KEY`
- Einrichtung der `.env`-Datei

**Wichtig:** Überprüfen Sie nach dem Skript die Datei `.env` und passen Sie folgende Werte an:

- `NEXT_PUBLIC_API_URL`: URL zum Backend (nicht `localhost` bei Remote-Zugriff)
- `SMTP_*`: E-Mail-Einstellungen für Benachrichtigungen

### 3. Starten der Anwendung

Laden Sie die Images herunter und starten Sie die Container:

```bash
docker-compose pull
docker-compose up -d
```

Nach wenigen Augenblicken ist die Anwendung erreichbar:

- **Frontend (App):** http://localhost:3011 (bzw. Ihre Domain)
- **Backend (API):** http://localhost:8011

---

## 🤖 KI-Konfiguration (Optional)

PhysioAI nutzt **Ollama** für lokale KI-Funktionen. Damit der Docker-Container auf Ihr lokales Ollama zugreifen kann, ist die Konfiguration bereits auf `host.docker.internal` vorbereitet.

### Schritt-für-Schritt Anleitung

1. **Installieren Sie Ollama** auf Ihrem Host-System:
   - Gehen Sie zu [Ollama.com](https://ollama.com/) und folgen Sie den Anweisungen für Linux/Mac/Windows

2. **Laden Sie das benötigte Modell:**

   ```bash
   ollama pull llama3.1:8b
   ```

3. **Starten Sie Ollama** so, dass es Anfragen akzeptiert:

   ```bash
   OLLAMA_HOST=0.0.0.0 ollama serve
   ```

---

## 📦 Updates

Um auf die neueste Version von PhysioAI zu aktualisieren:

```bash
# 1. Neueste Konfiguration holen (falls sich Variablen geändert haben)
git pull

# 2. Neueste Images von Docker Hub laden
docker-compose pull

# 3. Container neu erstellen (Datenbank bleibt erhalten!)
docker-compose up -d
```

---

## 💾 Backup & Daten

Die Daten werden in Docker-Volumes persistent gespeichert. Diese befinden sich im Standard-Docker-Verzeichnis, sofern nicht anders konfiguriert.

### Wichtige Volumes

- `physio-deploy_postgres_data`: Enthält die gesamte Datenbank
- `physio-deploy_redis_data`: Enthält temporäre Cache-Daten und Warteschlangen

### Backup-Empfehlung

Erstellen Sie regelmäßig Dumps der PostgreSQL-Datenbank:

```bash
docker exec -t physio_db pg_dumpall -c -U postgres > dump_$(date +%Y-%m-%d).sql
```

---

## ❓ Troubleshooting

### Container starten nicht?

Prüfen Sie die Logs:

```bash
docker-compose logs -f
```

### Fehler "Backend not found" im Frontend?

Stellen Sie sicher, dass `NEXT_PUBLIC_API_URL` in der `.env`-Datei korrekt auf die öffentliche IP oder Domain Ihres Servers zeigt (nicht `localhost`, wenn Sie von einem anderen Gerät zugreifen).

### KI antwortet nicht?

Prüfen Sie folgende Punkte:

- Ollama läuft auf dem Host
- Port 11434 ist offen
- Testen Sie es vom Host aus: `curl http://localhost:11434`

---

## ⚖️ Lizenz

Copyright © 2024 PhysioAI. Diese Software wird als proprietäre Lösung bereitgestellt. Die Weitergabe der Docker-Images oder des Quellcodes ohne Genehmigung ist untersagt.

Entwickelt mit ❤️ für die Physiotherapie.
