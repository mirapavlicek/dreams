#!/usr/bin/env python3
"""Malý HTTP server, který hodinkám servíruje stav schránky podle qmail.

Sesbírá `.eml` soubory ze zadané složky, každý prožene `qmail.screen_raw`
a výsledky složí do jednoho rozdělení |psi|^2 pro celou schránku:
průměr pravděpodobností přes e-maily je pořád platná hustota pravděpodobnosti
(nezáporná, sečtená na 1), takže prstenec na hodinkách ukazuje, kde v prostoru
verdiktů schránka jako celek "leží".

    python3 garmin/tools/qmail_server.py --mail-dir examples --port 8720

Adresu (`http://<ip>:8720/qmail.json`) pak stačí vyplnit v nastavení aplikace.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from qmail import screen_raw  # noqa: E402
from qmail.states import BASIS, Verdict  # noqa: E402

#: Klíče v JSONu pro hodinky - stabilní, na rozdíl od českých `Verdict.label`.
API_KEYS = {Verdict.HAM: "ham", Verdict.SPAM: "spam", Verdict.PHISHING: "phishing"}


def screen_directory(mail_dir: pathlib.Path) -> dict:
    """Prožene všechny .eml ve složce qmailem a složí z nich stav schránky."""
    paths = sorted(mail_dir.glob("*.eml"))
    totals = {verdict: 0.0 for verdict in BASIS}
    uncertainty = 0.0
    needs_review = 0

    for path in paths:
        result = screen_raw(path.read_bytes())
        for verdict, probability in result.probabilities.items():
            totals[verdict] += probability
        uncertainty += result.uncertainty
        needs_review += 1 if result.needs_review else 0

    count = len(paths)
    if count == 0:
        probabilities = {API_KEYS[Verdict.HAM]: 1.0, API_KEYS[Verdict.SPAM]: 0.0, API_KEYS[Verdict.PHISHING]: 0.0}
        return {
            "probabilities": probabilities,
            "uncertainty": 0.0,
            "needs_review": 0,
            "scanned": 0,
        }

    probabilities = {API_KEYS[verdict]: totals[verdict] / count for verdict in BASIS}
    peak = max(probabilities, key=probabilities.get)
    return {
        "verdict": peak,
        "probabilities": probabilities,
        "confidence": probabilities[peak],
        "uncertainty": uncertainty / count,
        "needs_review": needs_review,
        "scanned": count,
    }


def make_handler(mail_dir: pathlib.Path):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - jméno určuje BaseHTTPRequestHandler
            if self.path.split("?")[0] not in ("/", "/qmail.json"):
                self.send_error(404)
                return
            payload = json.dumps(screen_directory(mail_dir)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mail-dir", default=str(REPO_ROOT / "examples"), help="složka s .eml soubory")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8720)
    parser.add_argument("--once", action="store_true", help="jen vypsat JSON na stdout a skončit")
    args = parser.parse_args()

    mail_dir = pathlib.Path(args.mail_dir)
    if not mail_dir.is_dir():
        parser.error(f"{mail_dir} není složka")

    if args.once:
        print(json.dumps(screen_directory(mail_dir), indent=2, ensure_ascii=False))
        return 0

    server = ThreadingHTTPServer((args.host, args.port), make_handler(mail_dir))
    print(f"qmail endpoint: http://{args.host}:{args.port}/qmail.json  (složka {mail_dir})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
