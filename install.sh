#!/bin/bash
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

# === УДАЛЯЕМ ВСЁ СТАРОЕ (чтобы можно было перезапускать сколько угодно раз) ===
echo -e "${YELLOW}Останавливаем и удаляем старые сервисы (если были)...${NC}"

systemctl stop node_exporter 2>/dev/null || true
systemctl disable node_exporter 2>/dev/null || true
rm -f /etc/systemd/system/node_exporter.service

for service in binance_exporter bybit_exporter okx_exporter; do
    systemctl stop $service 2>/dev/null || true
    systemctl disable $service 2>/dev/null || true
    rm -f /etc/systemd/system/${service}.service
    rm -f /usr/local/bin/${service}.py
done

# Останавливаем процесс node_exporter, если он висит
pkill -f /usr/local/bin/node_exporter || true
sleep 2

# Удаляем сам бинарник (теперь точно можно)
rm -f /usr/local/bin/node_exporter

systemctl daemon-reload

echo -e "${GREEN}Старые компоненты удалены — можно устанавливать заново${NC}"
