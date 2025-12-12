#!/bin/bash
# ==================================================================
# Node Exporter + Ping Exporter (Binance / Bybit / OKX)
# Репозиторий: https://github.com/Bodiyx/script
# Одной командой:
# sudo sh -c "curl -fsSL https://raw.githubusercontent.com/Bodiyx/script/main/install.sh -o /tmp/install.sh && chmod +x /tmp/install.sh && /tmp/install.sh"
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
for s in node_exporter binance_exporter bybit_exporter okx_exporter; do
    systemctl stop $s 2>/dev/null || true
    systemctl disable $s 2>/dev/null || true
    rm -f /etc/systemd/system/${s}.service
done
pkill -9 -f node_exporter 2>/dev/null || true
pkill -9 -f '_exporter.py' 2>/dev/null || true
sleep 1
[ -f /usr/local/bin/node_exporter ] && > /usr/local/bin/node_exporter 2>/dev/null && rm -f /usr/local/bin/node_exporter
rm -f /usr/local/bin/*_exporter.py
systemctl daemon-reload >/dev/null 2>&1

# 2. Пользователь + node_exporter
id prometheus >/dev/null 2>&1 || useradd -rs /bin/false prometheus

echo -e "${ELLOW}Установка node_exporter 1.7.0...${NC}"
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/ 2>/dev/null || cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
rm -rf node_exporter-1.7.0*

mkdir -p /var/lib/node_exporter/textfile_collector
chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector

# 3. Выбор биржи
echo
echo "Выберите биржу:"
echo "1) Binance   2) Bybit   3) OKX"
echo -n "Номер (1-3): "
read choice
case $choice in 1) EXCHANGE="binance"; NAME="Binance" ;; 2) EXCHANGE="bybit"; NAME="Bybit" ;; 3) EXCHANGE="okx"; NAME="OKX" ;; *) echo -e "${RED}Ошибка${NC}"; exit 1 ;; esac

# 4. Скачивание экспортера
echo -e "${ELLOW}Скачиваем ${NAME}_exporter.py...${NC}"
wget -q --no-cache "https://raw.githubusercontent.com/Bodiyx/script/main/${EXCHANGE}_exporter.py" -O "/usr/local/bin/${EXCHANGE}_exporter.py"
chmod +x "/usr/local/bin/${EXCHANGE}_exporter.py"

# 5. Сервисы
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
ExecStart=/usr/local/bin/${EXCHANGE}_exporter.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter ${EXCHANGE}_exporter

# 6. ВПИСЫВАЕМСЯ В ЧУЖОЙ ФАЙРВОЛ — ПРАВИЛО ПОСЛЕ SSH
echo -e "${ELLOW}Вставляем порт 9100 сразу после правила SSH...${NC}"
update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true

echo
echo -e "${ELLOW}Порт 9100 будет доступен ТОЛЬКО с одного IP${NC}"
echo -n "Введите IP вашего Prometheus/Grafana: "
read allowed_ip
[[ -z "$allowed_ip" ]] && { echo -e "${RED}IP не введён${NC}"; exit 1; }

iptables -D INPUT -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT 2>/dev/null || true

SSH_LINE=$(iptables -L INPUT --line-numbers 2>/dev/null | grep "tcp dpt:22" | awk '{print $1}')
if [[ -n "$SSH_LINE" && "$SSH_LINE" =~ ^[0-9]+$ ]]; then
    iptables -I INPUT $((SSH_LINE + 1)) -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT
else
    iptables -A INPUT -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT
fi

iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

echo -e "${GREEN}ГОТОВО! Правило вставлено после SSH:${NC}"
iptables -L INPUT -n --line-numbers | grep -E "(dpt:22|dpt:9100|ACCEPT all -- anywhere|DROP all)" -A3 -B3

# 7. Финал
IP=$(hostname -I | awk '{print $1}')
echo
echo -e "${GREEN}УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo "Node Exporter      → http://$IP:9100/metrics"
echo "${NAME} Ping Exporter → http://$IP:XXXX/metrics"
echo
echo "Проверить: sudo iptables -L -n | grep 9100"

exit 0
