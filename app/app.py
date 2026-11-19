import os

from flask import Flask, jsonify
import requests
from datetime import datetime

app = Flask(__name__)

# All runtime settings come from environment variables (see .env.example).
IMDS = os.getenv("IMDS_ENDPOINT", "http://169.254.169.254/latest")
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "5000"))
APP_ENV = os.getenv("APP_ENV", "development")


def _imds_token():
    """Fetch an IMDSv2 session token (the instance enforces IMDSv2)."""
    r = requests.put(
        f"{IMDS}/api/token",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        timeout=1,
    )
    r.raise_for_status()
    return r.text


def _metadata(path):
    try:
        token = _imds_token()
        r = requests.get(
            f"{IMDS}/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
            timeout=1,
        )
        r.raise_for_status()
        return r.text
    except Exception:
        return "not running on an EC2 instance"


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/info")
def info():
    return jsonify({
        "instance_id": _metadata("instance-id"),
        "availability_zone": _metadata("placement/availability-zone"),
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "environment": APP_ENV,
    })


if __name__ == "__main__":
    app.run(host=HOST, port=PORT)
