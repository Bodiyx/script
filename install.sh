#!/bin/bash
# ==================================================================
# Node Exporter + Ping Exporter (Binance / Bybit / OKX)
# Репозиторий: https://github.com/Bodiyx/script
# Одной командой:
# sudo sh -c "wget -O /tmp/install.sh https://raw.githubusercontent.com/Bodiyx/script/main/install.sh && chmod +x /tmp/install.sh && /tmp/install.sh""
# ==================================================================

set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Запускай через sudo${NC}"
    exit 1
fi
clear
echo -e "${GREEN}Установка Node Exporter + Ping Exporter${NC}"
echo "════════════════════════════════════════════════"
# 1. Полная очистка старого
echo -e "${YELLOW}Удаляем старые настройки ...${NC}"
for s in node_exporter binance_exporter bybit_exporter okx_exporter; do
    systemctl stop $s 2>/dev/null || true
    systemctl disable $s 2>/dev/null || true
    rm -f /etc/systemd/system/${s}.service
done
pkill -f node_exporter 2>/dev/null || true
pkill -f '_exporter.py' 2>/dev/null || true
sleep 1
if [ -f /usr/local/bin/node_exporter ]; then
    > /usr/local/bin/node_exporter 2>/dev/null || true
    rm -f /usr/local/bin/node_exporter
fi
rm -f /usr/local/bin/*_exporter.py
systemctl daemon-reload >/dev/null 2>&1
# 2. Пользователь
id prometheus >/dev/null 2>&1 || useradd -rs /bin/false prometheus
# 3. node_exporter
echo -e "${YELLOW}Устанавливаем node_exporter 1.7.0...${NC}"
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/node_exporter.tmp
mv -f /usr/local/bin/node_exporter.tmp /usr/local/bin/node_exporter
chmod +x /usr/local/bin/node_exporter
rm -rf node_exporter-1.7.0*
# 4. textfile collector
mkdir -p /var/lib/node_exporter/textfile_collector
chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector
# 5. Выбор биржи
echo
echo "Выберите биржу:"
echo "1) Binance"
echo "2) Bybit"
echo "3) OKX"
echo -n "Номер (1-3): "
read choice
case $choice in 1) EXCHANGE="binance"; NAME="Binance" ;; 2) EXCHANGE="bybit"; NAME="Bybit" ;; 3) EXCHANGE="okx"; NAME="OKX" ;; *) echo -e "${RED}Неправильно!${NC}"; exit 1 ;; esac
# 6. Скачивание экспортера
echo -e "${YELLOW}Скачиваем ${NAME}_exporter.py...${NC}"
wget -q --no-cache "https://raw.githubusercontent.com/Bodiyx/script/main/${EXCHANGE}_exporter.py" -O "/usr/local/bin/${EXCHANGE}_exporter.py"
chmod +x "/usr/local/bin/${EXCHANGE}_exporter.py"
# 7. Сервисы
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/${EXCHANGE}_exporter.service << EOF
[Unit]
Description=${NAME} Ping Exporter
After=network.target
[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/bin/python3 /usr/local/bin/${EXCHANGE}_exporter.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now node_exporter ${EXCHANGE}_exporter
# 8. Firewall — без предупреждений и без ошибки позиции
echo -e "${YELLOW}Настраиваем firewall...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -yqq >/dev/null 2>&1
apt install -yqq iptables-persistent netfilter-persistent >/dev/null 2>&1
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
echo
echo -n "Введите IP вашего ядра: "
read allowed_ip
[[ -z "$allowed_ip" ]] && { echo -e "${RED}IP не введён${NC}"; exit 1; }
iptables -D INPUT -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT 2>/dev/null || true
LINE_NUM=$(sudo iptables -L INPUT -n --line-numbers | grep 'tcp dpt:22' | awk '{print $1}')
NEW_POS=$((LINE_NUM + 1))
iptables -I INPUT $NEW_POS -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT # без номера = всегда в начало
netfilter-persistent save >/dev/null 2>&1 || true
echo -e "${GREEN}Порт 9100 открыт только для $allowed_ip${NC}"

# 9. Настройка автоматического бэкапа профиля MoonTrader
echo
echo -e "${YELLOW}Настройка автоматического бэкапа профиля MoonTrader${NC}"
echo -n "Имя профиля ядра МТ, должно полностью совпадать: "
read profile_name
if [[ -z "$profile_name" ]]; then
    echo -e "${RED}Имя профиля не введено — пропускаем настройку бэкапа.${NC}"
else
    PY_FILE="/root/mt_backup.py"

    cat > "$PY_FILE" << EOF
import os
import tarfile
import datetime
import glob
import time

# === Конфигурация ===
SOURCE_DIR = "/root/.config/moontrader-data/data"
BACKUP_DIR = "/root/.config/moontrader-data/backup"
SEARCH_PATTERNS = [f"*{profile_name}*", "*.aes", "*.profile"]
RETENTION_DAYS = 5  # Хранить архивы не старше 5 дней
LOG_FILE = os.path.join(BACKUP_DIR, "backup_log.txt")


def log(msg):
    """Запись в лог с отметкой времени"""
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{ts}] {msg}\\n")
    print(msg)


def create_backup():
    """Создает tar.gz архив с текущей датой"""
    os.makedirs(BACKUP_DIR, exist_ok=True)

    log("Создание автоматического бэкапа профиля.")

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_name = f"backup_{timestamp}.tar.gz"
    archive_path = os.path.join(BACKUP_DIR, archive_name)

    # --- поиск файлов по шаблонам ---
    items_to_backup = set()
    for pattern in SEARCH_PATTERNS:
        items_to_backup.update(glob.glob(os.path.join(SOURCE_DIR, pattern)))

    if not items_to_backup:
        log("❌ Не найдены файлы для бэкапа.")
        return

    # --- создание архива ---
    try:
        with tarfile.open(archive_path, "w:gz") as tar:
            for path in items_to_backup:
                tar.add(path, arcname=os.path.basename(path))
        log(f"✅ Создан бэкап: {archive_path} ({len(items_to_backup)} файлов)")
    except Exception as e:
        log(f"❌ Ошибка при создании бэкапа: {e}")


def rotate_backups():
    """Удаляет архивы старше RETENTION_DAYS"""
    now = time.time()
    deleted_count = 0

    for path in glob.glob(os.path.join(BACKUP_DIR, "backup_*.tar.gz")):
        try:
            mtime = os.path.getmtime(path)
            age_days = (now - mtime) / 86400
            if age_days > RETENTION_DAYS:
                os.remove(path)
                log(f"🗑️ Удалён старый архив: {path} ({age_days:.1f} дн.)")
                deleted_count += 1
        except Exception as e:
            log(f"❌ Ошибка при удалении {path}: {e}")

    if deleted_count == 0:
        log("⏭️ Старых архивов для удаления нет.")


if __name__ == "__main__":
    create_backup()
    rotate_backups()
EOF

    chmod +x "$PY_FILE"
    echo -e "${GREEN}Создан исполняемый файл: $PY_FILE${NC}"

    # Добавляем в cron (ежедневно в 3:00)
    (crontab -l 2>/dev/null | grep -v "$PY_FILE"; echo "0 3 * * * /usr/bin/python3 $PY_FILE") | crontab -
    echo -e "${GREEN}Добавлена задача в cron: ежедневный запуск в 03:00${NC}"
fi

# 10. Готово
IP=$(hostname -I | awk '{print $1}')
echo
echo -e "${GREEN}УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo "Node Exporter → http://$IP:9100/metrics"
echo "${NAME} Ping Exporter → http://$IP:XXXX/metrics"
echo "Проверить: sudo iptables -L -n"
if [[ -n "$profile_name" ]]; then
    echo "Автоматический бэкап MT настроен (/root/mt_backup.py)"
fi
exit 0
