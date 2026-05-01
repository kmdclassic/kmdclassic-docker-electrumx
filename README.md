# Komodo ElectrumX Docker Setup

Docker Compose configuration for running ElectrumX server for Komodo.

## Requirements

- Docker
- Docker Compose
- Access to Komodo daemon at `127.0.0.1:7771` on the host machine

## Network Mode

The container uses `host` network mode, which means:
- The container shares the host's network stack
- Access to `127.0.0.1:7771` from the container will connect to the host's `127.0.0.1:7771`
- Ports `50001` (TCP), `50002` (SSL), `50004` (WSS), and `8000` (RPC) are directly exposed on the host

## Quick Start

### First Time Setup

1. Copy `.env.example` to `.env` and modify configuration if needed:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` file to set your configuration:
   ```bash
   nano .env  # or use your preferred editor
   ```
   
   Set the following values:
   - `PUID` and `PGID` - User and Group IDs (default: 1000)
   - `DAEMON_URL` - Komodo daemon RPC URL with credentials
   - `DOMAIN_NAME` - Domain name for SSL certificate (optional, for certbot)
   - `CF_API_TOKEN` - CloudFlare API token for DNS validation (optional, for certbot)
   - `CF_EMAIL` - Email for Let's Encrypt notifications (optional, for certbot)

3. Build and start the container:
   ```bash
   docker compose up -d
   ```

4. Check logs to verify it's running:
   ```bash
   docker compose logs -f
   ```

### Common Commands

**Start the container:**
```bash
docker compose up -d
```

**Stop the container:**
```bash
docker compose down
```

**View logs:**
```bash
# Follow logs in real-time
docker compose logs -f

# View last 100 lines
docker compose logs --tail=100

# View logs for specific service
docker compose logs electrumx
```

**Restart the container:**
```bash
docker compose restart
```

**Rebuild the image:**
```bash
# Rebuild without cache
docker compose build --no-cache

# Rebuild and start
docker compose up -d --build
```

**Check container status:**
```bash
docker compose ps
```

**Execute command in running container:**
```bash
docker compose exec electrumx sh
```

**View container resource usage:**
```bash
docker stats electrumx
```

## Configuration

All configuration parameters are set in `docker-compose.yml` via environment variables:

- `COIN=Komodo` - coin for indexing
- `DB_DIRECTORY=/data` - database directory
- `DAEMON_URL` - URL to connect to Komodo daemon (can be set in `.env` file, default: `http://rpcuser:rpcpassword@127.0.0.1:7771/`)
- `SERVICES` - ElectrumX services (TCP, SSL, WSS, and RPC). Default: `tcp://:50001,ssl://:50002,wss://:50004,rpc://:8000`
- `EVENT_LOOP_POLICY=uvloop` - use uvloop for better performance
- `PEER_DISCOVERY=self` - peer discovery mode
- `MAX_SESSIONS=1000` - maximum number of sessions
- `MAX_SEND=2000000` - maximum send size
- `INITIAL_CONCURRENT=50` - initial number of concurrent connections
- `COST_SOFT_LIMIT=1000` - per-session cost above which ElectrumX starts throttling requests by inserting a sleep before each response (the `request sleep` you see in startup logs). ElectrumX defaults to `1000`. Setting this to `0` makes every session look over-limit immediately, which throttles all clients to a crawl.
- `COST_HARD_LIMIT=10000` - per-session cost at which ElectrumX disconnects the client. ElectrumX defaults to `10000`. Setting this to `0` causes every session to exceed the hard limit on its first request, which is why a misconfigured `0` looks like the server "doesn't respond".
- `BANDWIDTH_UNIT_COST=5000` - number of bytes that count as one cost unit when accumulating session cost. ElectrumX defaults to `5000`. Higher values let sessions transfer more data before hitting the soft/hard limits.
- `PUID=1000` - User ID to run ElectrumX server (default: 1000)
- `PGID=1000` - Group ID to run ElectrumX server (default: 1000)

**Note:** `PUID` and `PGID` are runtime environment variables. The container will automatically create a user with the specified UID/GID at startup if it doesn't exist. You can use a pre-built image and set these values at runtime without rebuilding.

## Technical Details

### LevelDB Version

This setup uses **LevelDB 1.22** instead of the newer 1.23 version. LevelDB 1.23 introduced breaking changes that cause compatibility issues with the `plyvel` Python package, resulting in the following error when starting the server:

```
ImportError: Error relocating /app/venv/lib/python3.14/site-packages/plyvel/_plyvel.cpython-314-x86_64-linux-musl.so: _ZTIN7leveldb10ComparatorE: symbol not found
```

This issue is similar to the one described in [plyvel issue #114](https://github.com/wbolster/plyvel/issues/114). LevelDB 1.22 is compiled from source during the Docker image build process to ensure compatibility with `plyvel` and ElectrumX.

## Ports

With host network mode, the following ports are directly exposed on the host:
- `50001` - ElectrumX TCP service (unencrypted)
- `50002` - ElectrumX SSL service (TLS/SSL encrypted)
- `50004` - ElectrumX WSS service (WebSocket Secure)
- `8000` - ElectrumX RPC service (JSON-RPC over TCP)

### RPC Usage Example

You can interact with the RPC service using `nc` (netcat):

```bash
echo '{"method":"getinfo","params":[],"id":1}' | nc -w 1 127.0.0.1 8000 | jq .
```

The `-w 1` flag sets a 1-second timeout to prevent `nc` from waiting indefinitely.

## Volumes

- `./data` - directory for storing ElectrumX database
- `./ssl` - directory for storing SSL certificates (created by certbot)

## SSL Certificates

The setup includes a `certbot` service that automatically obtains and renews SSL certificates from Let's Encrypt using CloudFlare DNS API validation.

**Note:** SSL certificates are required for the SSL (`ssl://:50002`) and WSS (`wss://:50004`) services. The TCP service (`tcp://:50001`) works without SSL certificates.

### Automatic Certificate Management

The `certbot` service runs continuously and automatically:
- Checks for existing certificates on startup
- Obtains new certificates if they don't exist
- Checks certificate expiration (renewal if less than 30 days remaining)
- Copies certificates to `./ssl/<DOMAIN_NAME>/` with proper permissions
- Runs periodic checks (default: every 24 hours, configurable via `RENEWAL_INTERVAL`)

### Configuration

1. Configure CloudFlare API token in `.env`:
   ```bash
   DOMAIN_NAME=yourdomain.com
   CF_API_TOKEN=your_cloudflare_api_token
   CF_EMAIL=admin@yourdomain.com
   RENEWAL_INTERVAL=86400  # Check interval in seconds (default: 86400 = 24 hours)
   ```

2. Configure SSL certificate paths in `.env` based on your `DOMAIN_NAME`:
   ```bash
   SSL_CERTFILE=/ssl/yourdomain.com/fullchain.pem
   SSL_KEYFILE=/ssl/yourdomain.com/privkey.pem
   ```

3. Start the certbot service:
   ```bash
   docker compose up -d certbot
   ```

   The service will:
   - Obtain certificates on first run
   - Automatically check and renew certificates periodically
   - Keep running in the background

4. Certificates are stored in `./ssl/<DOMAIN_NAME>/`:
   - `fullchain.pem` - Full certificate chain
   - `privkey.pem` - Private key

5. The certificates are automatically mounted into the `electrumx` container at `/ssl` (read-only).

6. SSL environment variables (`SSL_CERTFILE` and `SSL_KEYFILE`) are automatically passed to the `electrumx` service and used for:
   - SSL service on port `50002` (TLS/SSL encrypted connections)
   - WSS service on port `50004` (WebSocket Secure connections)

**Important:** After certificate renewal, the `electrumx` service does **not** automatically restart. You need to manually restart it to load the new certificates:

```bash
docker compose restart electrumx
```

### Automatic ElectrumX Restart After Certificate Renewal

Since `electrumx` doesn't automatically reload certificates, it's recommended to set up an external script that restarts the service after certificate updates. You can use a cron job or systemd timer for this.

**Example script (`restart-electrumx-on-cert-update.sh`):**

```bash
#!/bin/bash
# Restart electrumx if SSL certificates were updated

CERT_DIR="./ssl"
COMPOSE_FILE="./docker-compose.yml"
LAST_CHECK_FILE="/tmp/electrumx-cert-last-check"

# Get the most recent modification time of certificate files
CERT_MTIME=$(find "$CERT_DIR" -name "*.pem" -type f -exec stat -c %Y {} \; 2>/dev/null | sort -n | tail -1)

# Check if certificates were updated since last check
if [ -f "$LAST_CHECK_FILE" ]; then
    LAST_CHECK=$(cat "$LAST_CHECK_FILE")
    if [ "$CERT_MTIME" -gt "$LAST_CHECK" ]; then
        echo "$(date): Certificates updated, restarting electrumx..."
        cd "$(dirname "$COMPOSE_FILE")"
        docker compose restart electrumx
    fi
else
    echo "$(date): First run, recording certificate state..."
fi

# Update last check time
echo "$CERT_MTIME" > "$LAST_CHECK_FILE"
```

**Set up a cron job (runs every hour):**

```bash
# Add to crontab: crontab -e
0 * * * * /path/to/restart-electrumx-on-cert-update.sh >> /var/log/electrumx-restart.log 2>&1
```

**Or use a systemd timer (runs every hour):**

Create `/etc/systemd/system/electrumx-cert-check.service`:
```ini
[Unit]
Description=Check and restart ElectrumX after certificate update

[Service]
Type=oneshot
WorkingDirectory=/path/to/kmdclassic-docker-electrumx
ExecStart=/path/to/restart-electrumx-on-cert-update.sh
```

Create `/etc/systemd/system/electrumx-cert-check.timer`:
```ini
[Unit]
Description=Check ElectrumX certificates hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

Then enable and start:
```bash
sudo systemctl enable electrumx-cert-check.timer
sudo systemctl start electrumx-cert-check.timer
```

**Note:** If file ownership issues occur, you may need to adjust permissions on the host:
```bash
sudo chown -R $PUID:$PGID ./ssl
```

### Manual Certificate Operations

If you need to manually trigger certificate operations:

**Check certificate status:**
```bash
docker compose exec certbot certbot certificates
```

**Force certificate renewal:**
```bash
docker compose exec certbot certbot renew --force-renewal --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini
```

**View certbot logs:**
```bash
docker compose logs -f certbot
```

## Stopping

```bash
docker compose down
```

## Rebuilding

If you need to rebuild the image:

```bash
docker compose build --no-cache
docker compose up -d
```

