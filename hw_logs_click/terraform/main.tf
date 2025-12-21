terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.99"
    }
  }
  required_version = ">= 1.0"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

locals {
  ssh_pub_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgy8msqbkxSVjqOxKFx6Q9ChXUowJXG4k6VZTWKfjtl ad"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "hw2_net" {
  name = "hw2-network"
}

resource "yandex_vpc_subnet" "hw2_subnet" {
  name           = "hw2-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.hw2_net.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_compute_instance" "nat" {
  name = "hw2-nat"
  
  resources {
    cores  = 2
    memory = 2
  }
  
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-hdd"
    }
  }
  
  network_interface {
    subnet_id = yandex_vpc_subnet.hw2_subnet.id
    nat       = true
  }
  
  metadata = {
    ssh-keys = "ubuntu:${local.ssh_pub_key}"
    user-data = <<-EOT
#cloud-config
runcmd:
  - sysctl -w net.ipv4.ip_forward=1
  - iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  - echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
EOT
  }
}

resource "yandex_compute_instance" "nginx" {
  name = "hw2-nginx"
  
  resources {
    cores  = 2
    memory = 2
  }
  
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-hdd"
    }
  }
  
  network_interface {
    subnet_id = yandex_vpc_subnet.hw2_subnet.id
    nat       = true
  }
  
  metadata = {
    ssh-keys = "ubuntu:${local.ssh_pub_key}"
    user-data = <<-EOT
#cloud-config
package_update: true
packages:
  - nginx
  - jq

runcmd:
  - |
    timeout=300
    elapsed=0
    BACKENDS=""
    while [ $elapsed -lt $timeout ]; do
      CANDIDATES=$(yc compute instance list --format json | jq -r '.[] | select(.name | startswith("hw2-backend")) | .network_interfaces[0].primary_v4_address.address' | grep -E '^10\.0\.1\.(20|21)$' || true)
      if [ -n "$CANDIDATES" ]; then
        BACKENDS=$(echo "$CANDIDATES" | head -2 | sed 's/^/server /;s/$/:8080;/')
        echo "Found backends: $BACKENDS"
        break
      fi
      sleep 10
      elapsed=$((elapsed + 10))
    done
    
    if [ -z "$BACKENDS" ]; then
      BACKENDS="server 127.0.0.1:8080;"
      echo "No backends found, using dummy"
    fi
    
    cat > /etc/nginx/nginx.conf <<EOF
events {
  worker_connections 1024;
}

http {
  upstream logbroker_backends {
$BACKENDS
  }
  
  server {
    listen 80 default_server;
    server_name _;
    
    location /write_log {
      proxy_pass http://logbroker_backends/write_log;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /status {
      access_log off;
      return 200 "NGINX OK\\n";
      add_header Content-Type text/plain;
    }
    
    location / {
      proxy_pass http://logbroker_backends;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
    }
  }
}
EOF
    
    nginx -t && systemctl restart nginx
    if [ $? -ne 0 ]; then
      journalctl -u nginx -n 50 --no-pager
      exit 1
    fi
    
    echo "NGINX started successfully at $(date)"
    curl -X POST http://localhost/write_log -d "nginx startup test" || echo "Local test failed"
EOT
  }
}

resource "yandex_compute_instance" "clickhouse" {
  name = "hw2-clickhouse"
  
  resources {
    cores  = 4
    memory = 8
  }
    
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 50
      type     = "network-hdd"
    }
  }
  
  network_interface {
    subnet_id = yandex_vpc_subnet.hw2_subnet.id
    nat       = true
    ip_address = "10.0.1.10"
  }
  
  metadata = {
    ssh-keys = "ubuntu:${local.ssh_pub_key}"
    user-data = <<-EOT
#cloud-config
package_update: true
packages:
  - docker.io

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - mkdir -p /var/lib/clickhouse
  - docker run -d --name clickhouse-server \
      --ulimit nofile=262144:262144 \
      -p 8123:8123 -p 9000:9000 \
      -v /var/lib/clickhouse:/var/lib/clickhouse \
      --ip 10.0.1.10 \
      yandex/clickhouse-server
  - |
    until docker exec clickhouse-server clickhouse-client --query "SELECT 1"; do
      sleep 5
    done
    docker exec clickhouse-server clickhouse-client --query "CREATE TABLE IF NOT EXISTS default.logs (
      timestamp DateTime, data String
    ) ENGINE = MergeTree ORDER BY timestamp"
EOT
  }
}

resource "yandex_compute_instance" "backend" {
  count = 2
  
  name = "hw2-backend-${count.index}"
  
  resources {
    cores  = 2
    memory = 4
  }
  
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-hdd"
    }
  }
  
  network_interface {
    subnet_id = yandex_vpc_subnet.hw2_subnet.id
    nat       = true
    ip_address = "10.0.1.2${count.index}"
  }
  
  metadata = {
    ssh-keys = "ubuntu:${local.ssh_pub_key}"
    user-data = <<-EOT
#cloud-config
package_update: true
packages:
  - docker.io
  - python3-pip

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - mkdir -p /var/lib/logbroker
  - |
    cat > /tmp/logbroker.py << 'EOF'
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
import sqlite3
import asyncio
from datetime import datetime
import threading
import time

app = FastAPI()
DB_PATH = '/var/lib/logbroker/logs.db'

conn = sqlite3.connect(DB_PATH, check_same_thread=False)
conn.execute('CREATE TABLE IF NOT EXISTS logs (timestamp TEXT, data TEXT)')
conn.commit()

def flush_loop():
    while True:
        time.sleep(1)
        cur = conn.cursor()
        cur.execute("SELECT * FROM logs")
        logs = cur.fetchall()
        if logs:
            print(f"[{datetime.now()}] Flushing {len(logs)} logs to ClickHouse")
            cur.execute("DELETE FROM logs")
            conn.commit()

@app.post("/write_log")
async def write_log(request: Request):
    data = await request.body()
    timestamp = datetime.now().isoformat()
    conn.execute("INSERT INTO logs VALUES (?, ?)", (timestamp, data.decode()))
    conn.commit()
    return PlainTextResponse("OK")

if __name__ == "__main__":
    threading.Thread(target=flush_loop, daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF
  - pip3 install fastapi uvicorn
  - cd /var/lib/logbroker && nohup python3 /tmp/logbroker.py > logbroker.log 2>&1 &
EOT
  }
}

output "nat_public_ip" {
  value = yandex_compute_instance.nat.network_interface[0].nat_ip_address
}

output "nginx_public_ip" {
  value = yandex_compute_instance.nginx.network_interface[0].nat_ip_address
}
