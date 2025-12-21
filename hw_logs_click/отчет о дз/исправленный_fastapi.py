from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
import sqlite3, threading, time, uvicorn, os, requests
from datetime import datetime

app = FastAPI()
DB_PATH = '/var/lib/logbroker/logs.db'
CLICKHOUSE_URL = "http://10.0.1.10:8123"
CLICKHOUSE_DB = "default"

conn = sqlite3.connect(DB_PATH, check_same_thread=False)
conn.execute('CREATE TABLE IF NOT EXISTS logs (timestamp TEXT, data TEXT)')
conn.commit()

def flush_to_clickhouse():
    global conn
    while True:
        try:
            time.sleep(5)
            cur = conn.cursor()
            cur.execute("SELECT * FROM logs")
            logs = cur.fetchall()
            
            if logs:
                values = ','.join([f"('{row[0]}','{row[1].replace(\"'\", \"\\\\'\") }')" for row in logs])
                ch_query = f"INSERT INTO default.logs (timestamp, data) FORMAT Values {values}"
                
                resp = requests.post(CLICKHOUSE_URL, data=ch_query)
                if resp.status_code == 200:
                    print(f"🚀 [{datetime.now()}] CLICKHOUSE: {len(logs)} логов отправлено!")
                    cur.execute("DELETE FROM logs")
                    conn.commit()
                else:
                    print(f"❌ ClickHouse error: {resp.status_code}")
        except Exception as e:
            print(f"❌ Flush error: {e}")

@app.get("/health")
async def health():
    return {"status": "OK", "logs": sqlite3.connect(DB_PATH).execute("SELECT COUNT(*) FROM logs").fetchone()[0]}

@app.post("/write_log")
async def write_log(request: Request):
    data = await request.body()
    timestamp = datetime.now().isoformat()
    conn.execute("INSERT INTO logs VALUES (?, ?)", (timestamp, data.decode()))
    conn.commit()
    return PlainTextResponse("OK")

threading.Thread(target=flush_to_clickhouse, daemon=True).start()
uvicorn.run(app, host="0.0.0.0", port=8080)
