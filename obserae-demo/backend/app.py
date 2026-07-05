#!/usr/bin/env python3
"""Minimal application backend for the obserae lab.

Each incoming HTTP request triggers a SQL query to PostgreSQL. This produces
the realistic flow chain:  workstation -> Caddy -> backend -> DB.
"""
import os
import time
import random

import psycopg2
from flask import Flask, jsonify

APP_ENV = os.environ.get("APP_ENV", "prod")
PGHOST = os.environ.get("PGHOST", "10.0.20.30")
PGPORT = int(os.environ.get("PGPORT", "5432"))
PGUSER = os.environ.get("PGUSER", "app")
PGPASSWORD = os.environ.get("PGPASSWORD", "app")
PGDATABASE = os.environ.get("PGDATABASE", "appdb")

app = Flask(__name__)


def db():
    return psycopg2.connect(
        host=PGHOST, port=PGPORT, user=PGUSER,
        password=PGPASSWORD, dbname=PGDATABASE, connect_timeout=3,
    )


@app.get("/health")
def health():
    return jsonify(status="ok", env=APP_ENV)


@app.get("/")
def index():
    """Simulate a business call: read from the database."""
    try:
        conn = db()
        cur = conn.cursor()
        cur.execute("SELECT id, name, city FROM customers ORDER BY random() LIMIT 3;")
        rows = [{"id": r[0], "name": r[1], "city": r[2]} for r in cur.fetchall()]
        cur.execute("SELECT count(*) FROM customers;")
        total = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify(env=APP_ENV, total_customers=total, sample=rows)
    except Exception as exc:  # noqa: BLE001
        return jsonify(env=APP_ENV, error=str(exc)), 503


if __name__ == "__main__":
    # Give PostgreSQL a moment to start.
    time.sleep(random.uniform(1, 3))
    app.run(host="0.0.0.0", port=8000)
