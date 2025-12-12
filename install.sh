#!/bin/bash

# ==================================================================
# Универсальный установщик Node Exporter + Ping Exporter (Binance / Bybit / OKX)
# Репозиторий со скриптами: https://github.com/Bodiyx/script
# Запуск: sudo bash install_ping_exporter.sh
# ==================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Скрипт нужно запускать от root (sudo)${NC}"
    exit 1
fi

clear
echo -e "${GREEN}Установка Node Exporter + Ping Exporter для биржи${NC}"
echo "══════════════════════════════════════════════════════════════"

# 1. Пользователь prometheus
echo -e "${YELLOW}Создание пользователя prometheus...${NC}"
id prometheus >/dev/null 2>&1 || useradd -rs /bin/false prometheus

# 2. Node Exporter 1.7.0
echo -e "${YELLOW}Установка node_exporter 1.7.0...${NC}"
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
rm -rf node_exporter-1.7.0.linux-amd64*

# 3. Директория textfile collector
echo -e "${YELLOW}Создание директории для textfile collector...${NC}"
mkdir -p /var/lib/node_exporter/textfile_collector
chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector

# 4. Выбор биржи
echo
echo "Выберите биржу:"
echo "1) Binance"
echo "2) Bybit"
echo "3) OKX"
echo -n "Введите номер (1-3): "
read choice

case $choice in
    1) EXCHANGE="binance"; NAME="Binance" ;;
    2) EXCHANGE="bybit";   NAME="Bybit"   ;;
    3) EXCHANGE="okx";     NAME="OKX"     ;;
    *) echo -e "${RED}Неверный выбор!${NC}"; exit 1 ;;
esac

# 5. Скачивание скрипта с твоего публичного репозитория
echo -e "${YELLOW}Скачивание ${NAME}_exporter.py из https://github.com/Bodiyx/script ...${NC}"
wget -q --no-cache \
    "https://raw.githubusercontent.com/Bodiyx/script/main/${EXCHANGE}_exporter.py" \
    -O "/usr/local/bin/${EXCHANGE}_exporter.py"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}Ошибка скачивания скрипта! Проверь интернет и ссылку.${NC}"
    exit 1
fi

chmod +x "/usr/local/bin/${EXCHANGE}_exporter.py"

# 6. Systemd сервис node_exporter
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

# 7. Systemd сервис выбранной биржи
cat > /etc/systemd/system/${EXCHANGE}_exporter.service << 'EOF'
[Unit]
Description=${NAME} Ping Exporter
After=network.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/${EXCHANGE}_exporter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 8. Запуск сервисов
systemctl daemon-reload
systemctl enable --now node_exporter
systemctl enable --now ${EXCHANGE}_exporter

echo -e "${GREEN}Сервисы node_exporter и ${EXCHANGE}_exporter запущены${NC}"

# 9. Открытие порта 9100
echo
echo "Настройка порта 9100 (node_exporter)"
echo -n "Разрешить доступ со всех IP? (y/n, по умолчанию y): "
read all_ip
if [[ $all_ip == "n" || $all_ip == "N" ]]; then
    echo -n "Введите разрешённый IP: "
    read allowed_ip
    allowed_ip=${allowed_ip:-0.0.0.0/0}
else
    allowed_ip="0.0.0.0/0"
    echo "Разрешён доступ со всех IP"
fi

# Установка iptables-persistent если нет
if ! dpkg -s netfilter-persistent >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt update
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent netfilter-persistent
fi

iptables -D INPUT -p tcp --dport 9100 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 6 -p tcp -s $allowed_ip --dport 9100 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || service netfilter-persistent save

echo -e "${GREEN}Порт 9100 открыт для $allowed_ip${NC}"

# 10. Финал
SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo
echo "Node Exporter      → http://$SERVER_IP:9100/metrics"
echo "${NAME} Ping Exporter → http://$SERVER_IP:XXXX/metrics  (порт смотри в скрипте)"
echo
echo "Проверить статус:"
echo "  systemctl status node_exporter"
echo "  systemctl status ${EXCHANGE}_exporter"
echo
echo "Готово!"

exit 0
