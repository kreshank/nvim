#!/usr/bin/env python3.12
"""Rewrite LSP JSON-RPC file URIs between a local SSHFS mount and the remote root.

Runs only on the local machine. The language server itself is started via the
command after ``--`` (typically ``ssh host clangd`` / ``pyright-langserver``).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
from urllib.parse import quote, unquote, urlparse, urlunparse


def _norm(path: str) -> str:
    path = path.replace("\\", "/")
    if len(path) > 1:
        path = path.rstrip("/")
    return path


def _rewrite_path(path: str, src: str, dst: str) -> str:
    if path == src or path.startswith(src + "/"):
        return dst + path[len(src) :]
    return path


def _rewrite_uri(uri: str, src: str, dst: str) -> str:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return uri

    raw_path = unquote(parsed.path)
    # file://host/path vs file:///path
    if parsed.netloc and not raw_path.startswith("/"):
        raw_path = "/" + parsed.netloc + raw_path

    new_path = _rewrite_path(raw_path, src, dst)
    if new_path == raw_path:
        return uri

    return urlunparse(
        (
            "file",
            "",
            quote(new_path, safe="/"),
            "",
            parsed.query,
            parsed.fragment,
        )
    )


def rewrite_value(value, src: str, dst: str):
    if isinstance(value, str):
        if value.startswith("file:"):
            return _rewrite_uri(value, src, dst)
        return _rewrite_path(value, src, dst)
    if isinstance(value, list):
        return [rewrite_value(item, src, dst) for item in value]
    if isinstance(value, dict):
        return {
            key: rewrite_value(item, src, dst) for key, item in value.items()
        }
    return value


def read_message(stream):
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            return None
        line = line.decode("utf-8") if isinstance(line, bytes) else line
        if line in ("\r\n", "\n"):
            break
        name, _, rest = line.partition(":")
        headers[name.strip().lower()] = rest.strip()

    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None

    chunks = []
    remaining = length
    while remaining > 0:
        chunk = stream.read(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)

    body = b"".join(chunks) if isinstance(chunks[0], (bytes, bytearray)) else "".join(chunks)
    if isinstance(body, str):
        body = body.encode("utf-8")
    return json.loads(body.decode("utf-8"))


def write_message(stream, payload: dict) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
    stream.write(header + body)
    stream.flush()


def pump(src, dst, src_root: str, dst_root: str) -> None:
    while True:
        message = read_message(src)
        if message is None:
            break
        write_message(dst, rewrite_value(message, src_root, dst_root))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-root", required=True)
    parser.add_argument("--remote-root", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("lsp-path-proxy: missing server command", file=sys.stderr)
        return 2

    local_root = _norm(os.path.abspath(args.local_root))
    remote_root = _norm(args.remote_root)

    proc = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
    )

    assert proc.stdin is not None
    assert proc.stdout is not None

    outgoing = threading.Thread(
        target=pump,
        args=(sys.stdin.buffer, proc.stdin, local_root, remote_root),
        daemon=True,
    )
    incoming = threading.Thread(
        target=pump,
        args=(proc.stdout, sys.stdout.buffer, remote_root, local_root),
        daemon=True,
    )
    outgoing.start()
    incoming.start()
    return proc.wait()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
