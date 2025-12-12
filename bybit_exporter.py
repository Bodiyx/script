#!/usr/bin/env python3
import time
import requests
from collections import deque

# Конфигурация
PROM_FILE = "/var/lib/node_exporter/textfile_collector/bybit.prom"
PING_URL = "https://api.bybit.com/v5/market/time"
INTERVAL = 3
WINDOW_HOURS = 3600
WINDOW_MIN = 60

MAX_PINGS_1H = WINDOW_HOURS // INTERVAL
MAX_PINGS_60S = WINDOW_MIN // INTERVAL

latencies_1h = deque(maxlen=MAX_PINGS_1H)
latencies_60s = deque(maxlen=MAX_PINGS_60S)

while True:
    try:
        t0 = time.time()
        requests.get(PING_URL, timeout=2)
        latency_ms = round((time.time() - t0) * 1000)
        status = 1
    except Exception:
        latency_ms = -1
        status = 0

    if latency_ms >= 0:
        latencies_1h.append(latency_ms)
        latencies_60s.append(latency_ms)

    max_latency_1h = max(latencies_1h) if latencies_1h else -1
    avg_latency_60s = round(sum(latencies_60s)/len(latencies_60s)) if latencies_60s else -1

    try:
        with open(PROM_FILE, "w") as f:
            f.write(f"bybit_latency_ms {latency_ms}\n")
            f.write(f"bybit_api_status {status}\n")
            f.write(f"bybit_latency_max_1h_ms {max_latency_1h}\n")
            f.write(f"bybit_latency_avg_60s_ms {avg_latency_60s}\n")
    except:
        pass

    time.sleep(INTERVAL)
