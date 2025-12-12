#!/bin/bash

# ==================================================================
# Node Exporter + Ping Exporter (Binance / Bybit / OKX)
# Репозиторий: https://github.com/Bodiyx/script
# Одной командой: sudo sh -c "curl -fsSL https://raw.githubusercontent.com/Bodiyx/script/main/install.sh -o /tmp/install.sh && chmod +x /tmp/install.sh && /tmp/install.sh"
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

# 1. Пользователь prometheus
id prometheus >/dev/null 2>&1 || useradd -rs /bin/false prometheus

# 2. node_exporter 1.7.0
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
rm -rf node_exporter-1.7.0*

# 3. textfile collector
mkdir -p /var/lib/node_exporter/textfile_collector
chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector

# 4. Выбор биржи
echo
echo "Выберите биржу:"
echo "1) Binance"
echo "2) Bybit"
echo "3) OKX"
echo -n "Номер (1-3): "
read choice

case $choice in
    1) EXCHANGE="binance"; NAME="Binance" ;;
    2) EXCHANGE="bybit";   NAME="Bybit"   ;;
    3) EXCHANGE="okx";     NAME="OKX"     ;;
    *) echo -e "${RED}Неправильно!${NC}"; exit 1 ;;
esac

# 5. Скачивание экспортера
echo -e "${YELLOW}Скачиваем ${NAME}_exporter.py...${NC}"
wget -q --no-cache \
    "https://raw.githubusercontent.com/Bodiyx/script/main/${EXCHANGE}_exporter.py" \
    -O "/usr/local/bin/${EXCHANGE}_exporter.py"
chmod +x "/usr/local/bin/${EXCHANGE}_exporter.py"

# 6. Сервис node_exporter
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

# 7. Сервис выбранной биржи
cat > /etc/systemd/system/${EXCHANGE}_exporter.service << EOF
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

# 9. Фикс iptables → legacy + установка persistent
echo -e "${YELLOW}Настраиваем firewall (iptables-legacy)...${NC}"
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent netfilter-persistent </dev/null

# Переключаемся на классический iptables (работает на всех новых Ubuntu)
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# 10. Обязательный ввод одного IP для порта 9100
echo
echo -e "${YELLOW}ВНИМАНИЕ: порт 9100 будет открыт ТОЛЬКО для одного IP${NC}"
echo -n "Введите IP вашего Prometheus/Grafana сервера: "
read allowed_ip

if [[ -z "$allowed_ip" ]]; then
    echo -e "${RED}Ошибка: IP не введён. Установка прервана.${NC}"
    exit 1
fi

# Удаляем старое правило (если было) и добавляем новое
iptables -D INPUT -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 6 -p tcp -s "$allowed_ip" --dport 9100 -j ACCEPT

# Сохраняем правила
netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4

echo -e "${GREEN}Порт 9100 открыт только для $allowed_ip${NC}"

# 11. Финал
IP=$(hostname -I | awk '{print $1}')
echo
echo -e "${GREEN}УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo
echo "Node Exporter      → http://$IP:9100/metrics"
echo "${NAME} Ping Exporter → http://$IP:XXXX/metrics (смотри порт в скрипте .py)"
echo
echo "Проверить статус:"
echo "  systemctl status node_exporter"
echo "  systemctl status ${EXCHANGE}_exporter"
echo
echo "Проверить firewall:"
echo "  sudo iptables -L -n -v"
echo

exit 0
