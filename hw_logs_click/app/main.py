import asyncio
import aiosqlite
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
import signal
import sys
import os
from datetime import datetime

app = FastAPI()
buffer_db = "log_buffer.db"
pending_logs = []

@app.on_event("startup")
async def startup():
    global db
    db = await aiosqlite.connect(buffer_db)
    await db.execute('''CREATE TABLE IF NOT EXISTS logs 
                        (timestamp TEXT, data TEXT)''')
    await db.commit()

@app.on_event("shutdown")
async def shutdown():
    await flush_all_logs()
    await db.close()

async def flush_all_logs():
    cursor = await db.execute("SELECT * FROM logs")
    logs = await cursor.fetchall()
    
    if logs:
        # Формируем батч для ClickHouse
        values = ",".join([f"('{row[0]}','{row[1]}')" for row in logs])
        query = f"INSERT INTO logs (timestamp, data) VALUES {values}"
        
        # TODO: замените на реальный ClickHouse клиент
        print(f"FLUSH: {len(logs)} logs sent to ClickHouse")
        
        # Очищаем буфер
        await db.execute("DELETE FROM logs")
        await db.commit()

async def buffer_log(timestamp: str, data: str):

    await db.execute("INSERT INTO logs (timestamp, data) VALUES (?, ?)", 
                     (timestamp, data))
    await db.commit()

@app.post("/write_log")
async def write_log(request: Request):

    data = await request.body()
    timestamp = datetime.now().isoformat()
    
    await buffer_log(timestamp, data.decode())
    pending_logs.append(data.decode())
    
    # Планируем flush через 1 секунду (если не запущен)
    asyncio.create_task(periodic_flush())
    
    return PlainTextResponse("OK")

async def periodic_flush():

    while True:
        await asyncio.sleep(1)
        await flush_all_logs()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
