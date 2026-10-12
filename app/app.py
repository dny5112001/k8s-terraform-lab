"""Tiny notes API. Stores each note as a JSON object in S3 (LocalStack in this lab)."""

import datetime
import json
import os
import socket
import uuid

import boto3
from botocore.config import Config
from flask import Flask, abort, jsonify, request

BUCKET = os.environ["NOTES_BUCKET"]
VERSION = os.environ.get("APP_VERSION", "dev")

# boto3 reads AWS_ENDPOINT_URL, AWS_REGION and the access keys from the environment.
# Path-style addressing because "<bucket>.localstack.localstack.svc..." won't resolve.
s3 = boto3.client("s3", config=Config(s3={"addressing_style": "path"}))

app = Flask(__name__)


@app.get("/")
def index():
    return {"service": "notes-api", "version": VERSION, "pod": socket.gethostname(), "bucket": BUCKET}


@app.get("/healthz")
def healthz():
    # Liveness: is the process alive? Never check dependencies here.
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    # Readiness: can we serve traffic? Kubernetes stops routing to us if this fails.
    try:
        s3.head_bucket(Bucket=BUCKET)
    except Exception as e:  # noqa: BLE001
        return {"status": "not ready", "error": str(e)}, 503
    return {"status": "ready"}


@app.post("/notes")
def create_note():
    body = request.get_json(silent=True) or {}
    text = (body.get("text") or "").strip()
    if not text:
        abort(400, "JSON body with a non-empty 'text' field is required")
    note = {
        "id": uuid.uuid4().hex[:12],
        "text": text,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "written_by": socket.gethostname(),
    }
    s3.put_object(Bucket=BUCKET, Key=f"notes/{note['id']}.json", Body=json.dumps(note), ContentType="application/json")
    return note, 201


@app.get("/notes")
def list_notes():
    resp = s3.list_objects_v2(Bucket=BUCKET, Prefix="notes/", MaxKeys=50)
    notes = [json.loads(s3.get_object(Bucket=BUCKET, Key=o["Key"])["Body"].read()) for o in resp.get("Contents", [])]
    return jsonify(sorted(notes, key=lambda n: n["created_at"], reverse=True))


@app.get("/notes/<note_id>")
def get_note(note_id):
    try:
        obj = s3.get_object(Bucket=BUCKET, Key=f"notes/{note_id}.json")
    except s3.exceptions.NoSuchKey:
        abort(404)
    return json.loads(obj["Body"].read())
