#!/usr/bin/env python3
"""Bounded calculator, daily reference rates, and runtime-only text clipboard."""
import ast
from datetime import date
import hashlib
import json
import math
import operator
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import urllib.request

MAX_TEXT = 32768
OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
       ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
       ast.Pow: operator.pow}


def private_dir(path):
    path = Path(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink() or path.stat().st_uid != os.getuid():
        raise ValueError("Invalid private directory")
    path.chmod(0o700)
    return path


def clipboard_db():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("No user runtime directory")
    directory = private_dir(Path(runtime) / "dotfiles-clipboard")
    path = directory / "history.sqlite"
    if path.is_symlink():
        raise ValueError("Invalid clipboard database")
    db = sqlite3.connect(path, timeout=2)
    path.chmod(0o600)
    db.execute("CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, body TEXT NOT NULL, updated INTEGER NOT NULL)")
    return db


def store_clipboard():
    raw = sys.stdin.buffer.read(MAX_TEXT + 1)
    if os.environ.get("CLIPBOARD_STATE") in ("sensitive", "nil", "clear") or len(raw) > MAX_TEXT:
        return
    text = raw.decode("utf-8")
    if not text.strip() or "\x00" in text:
        return
    with clipboard_db() as db:
        identity = hashlib.sha256(raw).hexdigest()
        db.execute("INSERT OR REPLACE INTO entries VALUES (?, ?, (SELECT COALESCE(MAX(updated),0)+1 FROM entries))", (identity, text))
        db.execute("DELETE FROM entries WHERE id NOT IN (SELECT id FROM entries ORDER BY updated DESC LIMIT 100)")


def calculate(expression):
    if len(expression) > 160:
        raise ValueError("Expression too long")
    tree = ast.parse(expression.replace("^", "**"), mode="eval")
    if len(list(ast.walk(tree))) > 64:
        raise ValueError("Expression too complex")

    def evaluate(node, depth=0):
        if depth > 16:
            raise ValueError("Expression too deep")
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            result = node.value
        elif isinstance(node, ast.Name) and node.id in ("pi", "e"):
            result = getattr(math, node.id)
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            result = evaluate(node.operand, depth + 1) * (-1 if isinstance(node.op, ast.USub) else 1)
        elif isinstance(node, ast.BinOp) and type(node.op) in OPS:
            left, right = evaluate(node.left, depth + 1), evaluate(node.right, depth + 1)
            if isinstance(node.op, ast.Pow) and abs(right) > 100:
                raise ValueError("Exponent too large")
            result = OPS[type(node.op)](left, right)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ("sqrt", "abs", "round") and len(node.args) == 1 and not node.keywords:
            result = {"sqrt": math.sqrt, "abs": abs, "round": round}[node.func.id](evaluate(node.args[0], depth + 1))
        else:
            raise ValueError("Unsupported expression")
        if not isinstance(result, (float, int)) or not math.isfinite(result) or abs(result) > 1e100:
            raise ValueError("Result out of range")
        return result

    return format(evaluate(tree.body), ".12g")


def rates(base):
    cache = private_dir(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-rates")
    path = cache / (base + ".json")
    data = None
    if path.exists() and not path.is_symlink():
        try:
            data = json.loads(path.read_text())
        except (ValueError, OSError):
            pass
    if not data or data.get("fetched") != date.today().isoformat():
        # Only the currency code is sent; never the amount or other search text.
        request = urllib.request.Request("https://api.frankfurter.dev/v1/latest?base=" + base,
                                         headers={"User-Agent": "Quickshell-Dotfiles/1.0", "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=4) as response:
            fresh = json.loads(response.read(65537))
        if fresh.get("base") != base or not isinstance(fresh.get("rates"), dict):
            raise ValueError("Invalid rate response")
        date.fromisoformat(fresh["date"])
        for code, value in fresh["rates"].items():
            if not re.fullmatch("[A-Z]{3}", code) or type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
                raise ValueError("Invalid rate")
        data = {**fresh, "fetched": date.today().isoformat()}
        fd, temporary = tempfile.mkstemp(dir=cache)
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream)
        os.replace(temporary, path)
    return data


def query(text):
    text = text.strip()
    if re.match(r"^(clip|clipboard)(?:\s|$)", text, re.I):
        search = text.split(maxsplit=1)[1].casefold() if len(text.split(maxsplit=1)) > 1 else ""
        with clipboard_db() as db:
            rows = db.execute("SELECT id,body FROM entries ORDER BY updated DESC").fetchall()
        return [{"id": "clip:" + identity, "name": " ".join(body.split())[:150],
                 "icon": "edit-paste", "toolAction": "clipboard", "value": identity}
                for identity, body in rows if search in body.casefold()][:50]
    if text.lower() == "clear clipboard":
        return [{"id": "clipboard:clear", "name": "Clear clipboard history", "icon": "edit-clear", "toolAction": "clear", "value": ""}]
    match = re.fullmatch(r"([+-]?\d+(?:\.\d{1,8})?)\s+([A-Za-z]{3})\s+(?:to|in)\s+([A-Za-z]{3})", text, re.I)
    if match:
        amount, base, target = float(match[1]), match[2].upper(), match[3].upper()
        if not math.isfinite(amount) or abs(amount) > 1e15:
            raise ValueError("Amount out of range")
        if base == target:
            value, stamp = amount, date.today().isoformat()
        else:
            table = rates(base)
            value, stamp = amount * table["rates"][target], table["date"]
        result = f"{value:,.2f} {target}"
        return [{"id": "currency", "name": f"{result} · reference rate {stamp}", "icon": "accessories-calculator", "toolAction": "copy", "value": result}]
    expression = text[1:].strip() if text.startswith("=") else text
    if text.startswith("=") or re.match(r"^[\d(.+-].*[+*/^%-]", expression):
        result = calculate(expression)
        return [{"id": "calculator", "name": result + " · Enter to copy", "icon": "accessories-calculator", "toolAction": "copy", "value": result}]
    return []


def action(kind, value):
    if kind == "clear":
        with clipboard_db() as db:
            db.execute("DELETE FROM entries")
        return
    if kind == "clipboard":
        with clipboard_db() as db:
            row = db.execute("SELECT body FROM entries WHERE id=?", (value,)).fetchone()
        if row is None:
            raise ValueError("Clipboard entry expired")
        value = row[0]
    elif kind != "copy":
        raise ValueError("Unknown action")
    if not isinstance(value, str) or len(value.encode()) > MAX_TEXT:
        raise ValueError("Invalid clipboard value")
    subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=value.encode(), check=True, timeout=3)


def main():
    os.umask(0o077)
    if len(sys.argv) > 1 and sys.argv[1] == "store":
        store_clipboard()
        return
    request = json.loads(sys.stdin.readline(65537))
    if request.get("op") == "query":
        print(json.dumps({"ok": True, "results": query(request["query"])}), flush=True)
    else:
        action(request.get("action"), request.get("value"))
        print('{"ok":true}', flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Clipboard/query content must not reach logs or exception tracebacks.
        if len(sys.argv) <= 1 or sys.argv[1] != "store":
            print('{"ok":false,"error":"No result — check the expression, currency, or connection"}', flush=True)
        sys.exit(1)
