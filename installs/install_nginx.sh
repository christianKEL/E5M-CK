#!/bin/sh
# ============================================================
# E5M-CK Nginx Installer
# Configure Nginx (already installed via Entware) as reverse proxy
# for Fluidd (port 4408) and Moonraker (upstream :7125)
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

# ─── Paths ─────────────────────────────────────────────────
NGINX_BIN="/opt/sbin/nginx"
NGINX_DIR="/usr/data/nginx"
NGINX_CONF="$NGINX_DIR/nginx.conf"
NGINX_LOGS="$NGINX_DIR/logs"
NGINX_TMP="$NGINX_DIR/tmp"
ENTWARE_NGINX_ETC="/opt/etc/nginx"
S50_SERVICE="/etc/init.d/S50nginx"

FLUIDD_DIR="/usr/data/fluidd"
MAINSAIL_DIR="/usr/data/mainsail"

# ─── ANSI COLORS (Red / White / Black theme) ───
RED='\033[0;31m'
BR_RED='\033[1;31m'
BG_RED='\033[41m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
DIM='\033[2m'
BLACK='\033[0;30m'
BG_BLACK='\033[40m'
BG_WHITE='\033[47m'
BOLD='\033[1m'
BLINK='\033[5m'
UNDER='\033[4m'
INV='\033[7m'
NC='\033[0m'

GREEN='\033[0;32m'
BR_GREEN='\033[1;32m'
YELLOW='\033[1;33m'

# ─── printf wrapper (safe %b format) ───
p() { printf "%b\n" "$1"; }

# ─── LOG FUNCTIONS ───
log_info()    { p "  ${WHITE}i${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_ok()      { p "  ${BR_GREEN}✓${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_warn()    { p "  ${YELLOW}!${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${YELLOW}$1${NC}"; }
log_error()   { p "  ${BR_RED}✗${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${BR_RED}$1${NC}"; }
log_action()  { p "  ${RED}>${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${DIM}$1${NC}"; }

# ─── STEP HEADER ───
log_step() {
    STEP_NUM=$1
    STEP_TITLE=$2
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP $STEP_NUM ${NC}  ${WHITE}${BOLD}$STEP_TITLE${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# ─── PAUSE UTILITY ───
pause_user() {
    p ""
    printf "  ${YELLOW}>${NC} ${WHITE}$1${NC}"
    read DUMMY
}

die() { log_error "$1"; exit 1; }

# ─── BIG ASCII BANNER ───
show_banner() {
    clear
    p ""
    p "${BR_RED}    ███████╗███████╗███╗   ███╗       ██████╗██╗  ██╗${NC}"
    p "${BR_RED}    ██╔════╝██╔════╝████╗ ████║      ██╔════╝██║ ██╔╝${NC}"
    p "${BR_RED}    █████╗  ███████╗██╔████╔██║█████╗██║     █████╔╝${NC}"
    p "${BR_RED}    ██╔══╝  ╚════██║██║╚██╔╝██║╚════╝██║     ██╔═██╗${NC}"
    p "${BR_RED}    ███████╗███████║██║ ╚═╝ ██║      ╚██████╗██║  ██╗${NC}"
    p "${BR_RED}    ╚══════╝╚══════╝╚═╝     ╚═╝       ╚═════╝╚═╝  ╚═╝${NC}"
    p ""
    p "${WHITE}             Nginx Installer${NC}"
    p "${GRAY}              for Creality Ender 5 Max (Nebula Pad)${NC}"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    p "${DIM}                 github.com/christianKEL/E5M-CK${NC}"
    p ""
}

# ─── DISCLAIMER ───
show_disclaimer() {
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  DISCLAIMER  ${NC}                                                   ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}This installer configures ${BOLD}Nginx${NC}${WHITE} (already installed via Entware)${NC}"
    p "  ${WHITE}as a reverse proxy for Fluidd and Moonraker.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} create ${DIM}/usr/data/nginx/${NC}${WHITE} (logs, tmp dirs)${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} write nginx.conf with HTTP/4408 → Fluidd, /4409 → Mainsail"
    p "  ${WHITE}  ${BR_RED}>${NC} reverse-proxy /printer/, /api/, /websocket → Moonraker (:7125)"
    p "  ${WHITE}  ${BR_RED}>${NC} install ${DIM}$S50_SERVICE${NC}${WHITE} (init script)${NC}"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}Nginx is NOT started by this script. Klipper, Moonraker, Fluidd${NC}"
    p "     ${WHITE}and Nginx will all start together once everything is in place.${NC}"
    p ""
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Nebula Pad, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${WHITE}Everyone using this installer is assumed to have a brain and${NC}"
    p "  ${WHITE}the ability to figure things out on their own.${NC}"
    p ""
    p "  ${WHITE}${BOLD}CR*ALITY S*CKS${NC} ${WHITE}is a humorous expression, NOT defamation.${NC}"
    p "  ${WHITE}Their team should have provided a working printer so we didn't${NC}"
    p "  ${WHITE}need to build this tool in the first place.${NC}"
    p ""
    p "  ${DIM}Signed: Christian KELHETTER${NC}"
    p "  ${DIM}github.com/christianKEL${NC}"
    p "  ${DIM}https://e5mdocumentation.kinsta.cloud/${NC}"
    p ""
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  ♥  SUPPORT THIS WORK  ♥  ${NC}                                    ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}If this installer saved you hours of work, please consider${NC}"
    p "  ${WHITE}buying me a ${BOLD}spool of filament${NC}${WHITE} as a thank you:${NC}"
    p ""
    p "  ${BR_RED}>${NC} ${UNDER}${WHITE}https://www.paypal.com/donate?token=6lw51uQOrrDBLN32dn5JPMpL0HSA8vMrRfjZSHFmQKXYKCddr1LHHpuKWCNTPMiqj2kIly1n5nmP0U6R${NC}"
    p ""
    pause_user "Press ENTER to continue..."
}

# ─── PRECHECK ───
step_precheck() {
    log_step "0" "Pre-flight checks"

    log_info "Checking nginx binary (Entware)..."
    if [ ! -x "$NGINX_BIN" ]; then
        die "$NGINX_BIN not found. Run install_entware.sh first."
    fi
    NGINX_VER=$($NGINX_BIN -v 2>&1)
    log_ok "Nginx found: $NGINX_VER"

    log_info "Checking nginx mime.types..."
    if [ ! -f "$ENTWARE_NGINX_ETC/mime.types" ]; then
        die "$ENTWARE_NGINX_ETC/mime.types missing. Reinstall nginx-ssl from Entware."
    fi
    log_ok "mime.types present"

    log_info "Checking Klipper installation..."
    if [ ! -d "/usr/data/klipper" ]; then
        log_warn "Klipper not found — Nginx will still install, but you'll need it"
    else
        log_ok "Klipper found"
    fi

    log_info "Checking Moonraker installation..."
    if [ ! -x "/usr/data/moonraker/moonraker-env/bin/python" ]; then
        log_warn "Moonraker not found — Nginx proxy targets won't respond yet"
    else
        log_ok "Moonraker found"
    fi

    log_info "Checking ports 4408 and 4409..."
    for port in 4408 4409; do
        if netstat -ln 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            log_warn "Port $port already in use — Nginx start may fail later"
        else
            log_action "Port $port is free"
        fi
    done
    log_ok "Port check done"
}

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Nginx binary :${NC} ${DIM}$NGINX_BIN${NC}"
    p "  ${WHITE}Working dir  :${NC} ${DIM}$NGINX_DIR${NC}"
    p "  ${WHITE}Conf file    :${NC} ${DIM}$NGINX_CONF${NC}"
    p "  ${WHITE}Init script  :${NC} ${DIM}$S50_SERVICE${NC}"
    p ""
    p "  ${WHITE}Routes:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} ${DIM}http://<ip>:4408/${NC}     ${WHITE}→ Fluidd${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} ${DIM}http://<ip>:4409/${NC}     ${WHITE}→ Mainsail (reserved)${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} ${DIM}/printer/, /api/, ...${NC} ${WHITE}→ Moonraker (proxy_pass :7125)${NC}"
    p ""
    if [ -f "$NGINX_CONF" ]; then
        p "  ${YELLOW}!  Existing $NGINX_CONF will be replaced.${NC}"
        p ""
    fi
    if [ -f "$S50_SERVICE" ]; then
        p "  ${YELLOW}!  Existing $S50_SERVICE will be replaced.${NC}"
        p ""
    fi
    printf "  ${WHITE}Continue? [Y/n]: ${NC}"
    read CONFIRM
    case "$CONFIRM" in
        n|N|no|NO)
            p ""
            log_warn "Cancelled by user"
            p ""
            exit 0
            ;;
    esac
}

# ─── STEP 1 — CREATE STRUCTURE ───
step_create_dirs() {
    log_step "1" "Create nginx directory structure"

    log_info "Creating $NGINX_DIR..."
    mkdir -p "$NGINX_LOGS" "$NGINX_TMP" "$NGINX_TMP/client_body" \
             "$NGINX_TMP/proxy" "$NGINX_TMP/fastcgi" "$NGINX_TMP/uwsgi" \
             "$NGINX_TMP/scgi" || die "Failed to create dirs"
    log_action "$NGINX_LOGS"
    log_action "$NGINX_TMP/{client_body,proxy,fastcgi,uwsgi,scgi}"

    log_info "Linking mime.types from Entware..."
    rm -f "$NGINX_DIR/mime.types"
    ln -s "$ENTWARE_NGINX_ETC/mime.types" "$NGINX_DIR/mime.types" \
        || die "symlink failed"
    log_action "$NGINX_DIR/mime.types -> $ENTWARE_NGINX_ETC/mime.types"

    log_ok "Directory structure ready"
}

# ─── STEP 2 — WRITE NGINX.CONF ───
step_write_conf() {
    log_step "2" "Write nginx.conf"

    if [ -f "$NGINX_CONF" ]; then
        log_info "Backing up existing conf to ${NGINX_CONF}.bak..."
        mv "$NGINX_CONF" "${NGINX_CONF}.bak"
    fi

    log_info "Generating nginx.conf..."
    cat > "$NGINX_CONF" <<'NGINX_CONF_EOF'
# ===========================================================
# Nginx config for E5M-CK
# - port 4408 : Fluidd UI
# - port 4409 : Mainsail UI (reserved for future install)
# - /printer/, /api/, /access/, /machine/, /server/, /websocket
#   → reverse-proxied to Moonraker on 127.0.0.1:7125
# - /webcam/ → mjpgstreamer (commented, uncomment when webcam installed)
# ===========================================================

worker_processes  1;
error_log         /usr/data/nginx/logs/error.log warn;
pid               /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /usr/data/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log    /usr/data/nginx/logs/access.log main;

    # Performance
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 4096;
    server_tokens off;

    # Gzip
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   6;
    gzip_types        text/plain text/css text/xml application/json
                      application/javascript application/xml+rss
                      application/atom+xml image/svg+xml;

    # Upload size (G-code files can be huge)
    client_max_body_size       2048M;
    client_body_buffer_size    32k;
    client_body_temp_path      /usr/data/nginx/tmp/client_body;
    proxy_temp_path            /usr/data/nginx/tmp/proxy;
    fastcgi_temp_path          /usr/data/nginx/tmp/fastcgi;
    uwsgi_temp_path            /usr/data/nginx/tmp/uwsgi;
    scgi_temp_path             /usr/data/nginx/tmp/scgi;

    # ─── Upstreams ──────────────────────────────────────────
    upstream apiserver {
        ip_hash;
        server 127.0.0.1:7125;
    }

    # mjpgstreamer (webcam) — uncomment when a webcam is installed
    # upstream mjpgstreamer {
    #     ip_hash;
    #     server 127.0.0.1:8080;
    # }

    # ─── Common Moonraker proxy locations ───────────────────
    # Defined as a map fragment via include directives below.

    # ─── Server : Fluidd on port 4408 ───────────────────────
    server {
        listen       4408 default_server;
        listen       [::]:4408 default_server;
        server_name  _;

        access_log /usr/data/nginx/logs/fluidd-access.log;
        error_log  /usr/data/nginx/logs/fluidd-error.log;

        # Fluidd web UI (static files)
        root /usr/data/fluidd;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        # Moonraker API proxy
        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://apiserver;
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme $scheme;
        }

        # Moonraker websocket
        location /websocket {
            proxy_pass http://apiserver/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme $scheme;
            proxy_read_timeout 86400;
        }

        # Webcam stream (uncomment when webcam installed)
        # location /webcam/ {
        #     proxy_pass http://mjpgstreamer/;
        #     proxy_http_version 1.1;
        #     proxy_set_header Host $http_host;
        # }
    }

    # ─── Server : Mainsail on port 4409 (reserved) ──────────
    # Active only if /usr/data/mainsail exists. If not, port 4409 returns 404
    # but does not break Nginx startup.
    server {
        listen       4409;
        listen       [::]:4409;
        server_name  _;

        access_log /usr/data/nginx/logs/mainsail-access.log;
        error_log  /usr/data/nginx/logs/mainsail-error.log;

        root /usr/data/mainsail;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html =404;
        }

        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://apiserver;
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme $scheme;
        }

        location /websocket {
            proxy_pass http://apiserver/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 86400;
        }
    }
}
NGINX_CONF_EOF

    if [ ! -s "$NGINX_CONF" ]; then
        die "Failed to write $NGINX_CONF"
    fi

    chmod 644 "$NGINX_CONF"
    SIZE=$(wc -c < "$NGINX_CONF")
    log_ok "Wrote $NGINX_CONF ($SIZE bytes)"
}

# ─── STEP 3 — WRITE INIT SCRIPT ───
step_write_service() {
    log_step "3" "Write S50nginx init script"

    if [ -f "$S50_SERVICE" ]; then
        log_info "Backing up existing service to ${S50_SERVICE}.bak..."
        cp "$S50_SERVICE" "${S50_SERVICE}.bak"
    fi

    log_info "Generating $S50_SERVICE..."
    cat > "$S50_SERVICE" <<'S50_EOF'
#!/bin/sh
#
# Nginx init script for E5M-CK
# Wraps /opt/sbin/nginx (Entware) with our custom conf at /usr/data/nginx
#

NAME=nginx
PROG=/opt/sbin/nginx
CONF=/usr/data/nginx/nginx.conf
PID_FILE=/var/run/nginx.pid

start() {
    if [ ! -x "$PROG" ]; then
        echo "Error: $PROG not found"
        exit 1
    fi
    if [ ! -f "$CONF" ]; then
        echo "Error: $CONF not found"
        exit 1
    fi
    # Test config before starting
    if ! "$PROG" -t -c "$CONF" >/dev/null 2>&1; then
        echo "Error: nginx config test failed"
        "$PROG" -t -c "$CONF"
        exit 1
    fi
    echo "Starting $NAME..."
    "$PROG" -c "$CONF"
}

stop() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Stopping $NAME..."
        "$PROG" -c "$CONF" -s quit
        # Wait up to 5s for graceful shutdown
        for i in 1 2 3 4 5; do
            [ -f "$PID_FILE" ] || break
            sleep 1
        done
        # Force kill if still running
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE" 2>/dev/null)
            [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null
            rm -f "$PID_FILE"
        fi
    else
        echo "$NAME is not running"
    fi
}

restart() {
    stop
    sleep 1
    start
}

reload() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Reloading $NAME..."
        "$PROG" -c "$CONF" -s reload
    else
        echo "$NAME not running, starting..."
        start
    fi
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "$NAME is running (PID $(cat $PID_FILE))"
        return 0
    else
        echo "$NAME is not running"
        return 1
    fi
}

case "$1" in
    start)   start   ;;
    stop)    stop    ;;
    restart) restart ;;
    reload)  reload  ;;
    status)  status  ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload|status}"
        exit 1
        ;;
esac

exit $?
S50_EOF

    if [ ! -s "$S50_SERVICE" ]; then
        die "Failed to write $S50_SERVICE"
    fi

    chmod 755 "$S50_SERVICE"
    SIZE=$(wc -c < "$S50_SERVICE")
    log_ok "Wrote $S50_SERVICE ($SIZE bytes, executable)"
}

# ─── STEP 4 — TEST CONFIG ───
step_test_conf() {
    log_step "4" "Test Nginx configuration"

    log_info "Running nginx -t -c $NGINX_CONF..."
    p ""

    OUTPUT=$($NGINX_BIN -t -c "$NGINX_CONF" 2>&1)
    EXIT_CODE=$?

    # Echo the test output line by line
    echo "$OUTPUT" | while read line; do
        log_action "$line"
    done

    p ""
    if [ "$EXIT_CODE" -eq 0 ]; then
        log_ok "Config syntax is OK"
    else
        log_error "Config test failed (exit code $EXIT_CODE)"
        die "Aborting — fix the conf manually and rerun"
    fi
}

# ─── STEP 5 — VERIFY ───
step_verify() {
    log_step "5" "Verify installation"

    p ""
    p "  ${WHITE}Check                          Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    # Nginx binary
    if [ -x "$NGINX_BIN" ]; then
        VER=$($NGINX_BIN -v 2>&1)
        p "  ${BR_GREEN}✓${NC} ${WHITE}Nginx binary${NC}                  ${DIM}$VER${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Nginx binary${NC}                  ${BR_RED}MISSING${NC}"
    fi

    # Conf
    if [ -f "$NGINX_CONF" ]; then
        SIZE=$(wc -c < "$NGINX_CONF")
        p "  ${BR_GREEN}✓${NC} ${WHITE}nginx.conf${NC}                    ${DIM}$SIZE bytes${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}nginx.conf${NC}                    ${BR_RED}MISSING${NC}"
    fi

    # Init script
    if [ -x "$S50_SERVICE" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}S50nginx${NC}                      ${DIM}executable${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}S50nginx${NC}                      ${BR_RED}NOT executable${NC}"
    fi

    # Dirs
    ALL_DIRS_OK=1
    for dir in "$NGINX_LOGS" "$NGINX_TMP/client_body" "$NGINX_TMP/proxy"; do
        [ -d "$dir" ] || ALL_DIRS_OK=0
    done
    if [ "$ALL_DIRS_OK" -eq 1 ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Working dirs${NC}                  ${DIM}logs/, tmp/{client_body,proxy,...}${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Working dirs${NC}                  ${BR_RED}some missing${NC}"
    fi

    # mime.types symlink
    if [ -L "$NGINX_DIR/mime.types" ] && [ -e "$NGINX_DIR/mime.types" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}mime.types${NC}                    ${DIM}-> $ENTWARE_NGINX_ETC/mime.types${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}mime.types${NC}                    ${BR_RED}symlink missing or broken${NC}"
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  NGINX INSTALLER COMPLETE  ${NC}                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Nginx is configured but ${BOLD}NOT started${NC}${WHITE}.${NC}                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Routes ready:${NC}                                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}http://<ip>:4408/      → Fluidd (need install_fluidd.sh)${NC}      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}http://<ip>:4409/      → Mainsail (reserved)${NC}                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/printer/, /api/, /websocket → Moonraker :7125${NC}                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Manage Nginx:${NC}                                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S50nginx {start|stop|restart|reload|status}${NC}       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Next: ${BOLD}install_fluidd.sh${NC}                                         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}

# ─── MAIN ───
main() {
    show_banner
    show_disclaimer
    show_banner
    step_precheck
    confirm_install
    step_create_dirs
    step_write_conf
    step_write_service
    step_test_conf
    step_verify
    show_completion
}

main "$@"
