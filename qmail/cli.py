"""Příkazová řádka: ``python -m qmail soubor.eml`` nebo přes stdin.

Vypíše kvantový verdikt: pravděpodobnosti |psi|^2 jednotlivých stavů,
neurčitost (entropii), seznam signálů a finální kolaps.

Pomocí ``--db`` lze zapojit *observatoř* - sdílenou paměť pozorovatelů.
Dřívější měření (vlastní i cizí) shodných rysů (odesílatel, doména odkazu,
předmět) pak ovlivní prior aktuálního e-mailu (role pozorovatele).
"""

from __future__ import annotations

import argparse
import json
import sys

from .observatory import Observatory
from .parser import parse_email
from .screen import ScreenResult, screen_email
from .states import BASIS, Verdict

_COLORS = {
    Verdict.HAM: "\033[92m",       # zelená
    Verdict.SPAM: "\033[93m",      # žlutá
    Verdict.PHISHING: "\033[91m",  # červená
}
_RESET = "\033[0m"


def _bar(p: float, width: int = 24) -> str:
    filled = int(round(p * width))
    return "#" * filled + "-" * (width - filled)


def _render_signal_lines(signals, lines: list[str]) -> None:
    for s in signals:
        contrib = ", ".join(
            f"{v.label} {abs(a):.2f}" for v, a in s.contributions.items()
        )
        damp = ", ".join(f"{v.label} x{f:.2f}" for v, f in s.damping.items())
        lines.append(f"  - [{s.name}] {s.detail}")
        if contrib:
            lines.append(f"      amplitudy: {contrib}")
        if damp:
            lines.append(f"      útlum: {damp}")


def _render_text(result: ScreenResult, color: bool, source: str = "") -> str:
    lines: list[str] = []
    lines.append("=" * 56)
    title = "KVANTOVÁ KONTROLA E-MAILU (|psi|^2)"
    if source:
        title += f"  [{source}]"
    lines.append(title)
    lines.append("=" * 56)
    lines.append("")
    lines.append("Hustota pravděpodobnosti verdiktů:")
    for v in BASIS:
        p = result.probabilities[v]
        c = _COLORS[v] if color else ""
        r = _RESET if color else ""
        lines.append(f"  {c}{v.label:<11}{r} |{_bar(p)}| {p:6.1%}")
    lines.append("")

    c = _COLORS[result.verdict] if color else ""
    r = _RESET if color else ""
    lines.append(f"Kolaps (verdikt):   {c}{result.verdict.label.upper()}{r}")
    lines.append(f"Důvěra (špička):    {result.confidence:.1%}")
    lines.append(f"Neurčitost (entrop.): {result.uncertainty:.3f}  (0=jisté, 1=zcela rozmazané)")
    lines.append(f"Čistota stavu:      {result.purity:.3f}")
    if result.needs_review:
        lines.append("  ! Stav je málo lokalizovaný -> doporučena lidská kontrola.")
    lines.append("")

    if result.history_signals:
        lines.append(f"Vliv pozorovatelů / historie ({len(result.history_signals)}):")
        _render_signal_lines(result.history_signals, lines)
        lines.append("")

    content_signals = [s for s in result.signals if s not in result.history_signals]
    if content_signals:
        lines.append(f"Obsahové signály ({len(content_signals)}):")
        _render_signal_lines(content_signals, lines)
    elif not result.history_signals:
        lines.append("Žádné podezřelé signály - stav zůstal blízko prior |ham>.")
    lines.append("=" * 56)
    return "\n".join(lines)


def _read_raw(path: str | None) -> bytes:
    if path:
        with open(path, "rb") as fh:
            return fh.read()
    return sys.stdin.buffer.read()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="qmail",
        description="Kvantově inspirovaná kontrola e-mailů proti phishingu a spamu.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Cesty k .eml souborům (lze více, zpracují se v pořadí). "
             "Bez nich se čte jeden e-mail ze stdin.",
    )
    parser.add_argument("--json", action="store_true", help="Výstup ve formátu JSON.")
    parser.add_argument(
        "--shots", type=int, default=0,
        help="Provede N pravděpodobnostních měření a vypíše empirické rozdělení.",
    )
    parser.add_argument("--no-color", action="store_true", help="Vypne barevný výstup.")
    parser.add_argument(
        "--db", metavar="PATH",
        help="Soubor observatoře (paměť pozorovatelů). Načte se a po zápisu uloží.",
    )
    parser.add_argument(
        "--observer", default="local", metavar="JMENO",
        help="Identita pozorovatele zapisujícího do observatoře (výchozí: local).",
    )
    parser.add_argument(
        "--record", action="store_true",
        help="Zaznamená výsledný verdikt do observatoře (ovlivní další e-maily).",
    )
    parser.add_argument(
        "--report", choices=[v.label for v in BASIS], metavar="VERDIKT",
        help="Zaznamená do observatoře explicitní verdikt (ham/spam/phishing) "
             "místo vypočteného - např. hlášení od jiného pozorovatele.",
    )
    args = parser.parse_args(argv)

    observatory: Observatory | None = None
    if args.db:
        observatory = Observatory.load(args.db)

    sources: list[str | None] = args.paths if args.paths else [None]
    results_json: list[dict] = []
    worst_code = 0
    db_changed = False

    for path in sources:
        raw = _read_raw(path)
        mail = parse_email(raw)
        result = screen_email(mail, observatory=observatory)

        # Záznam do observatoře (tento e-mail se stane součástí historie).
        if observatory is not None and (args.record or args.report):
            if args.report:
                rec_verdict = next(v for v in BASIS if v.label == args.report)
            else:
                rec_verdict = result.verdict
            observatory.record(mail, rec_verdict, observer=args.observer)
            db_changed = True

        if args.json:
            entry = result.as_dict()
            if path:
                entry["source"] = path
            if args.shots > 0:
                entry["sampled"] = {
                    v.label: p
                    for v, p in result.sample_distribution(args.shots, seed=0).items()
                }
            results_json.append(entry)
        else:
            color = sys.stdout.isatty() and not args.no_color
            print(_render_text(result, color=color, source=path or "stdin"))
            if args.shots > 0:
                sampled = result.sample_distribution(args.shots, seed=0)
                print(f"\n{args.shots}x měření (empirický kolaps):")
                for v in BASIS:
                    print(f"  {v.label:<11} {sampled[v]:6.1%}")
            print()

        if result.verdict != Verdict.HAM:
            worst_code = 2

    if observatory is not None and args.db and db_changed:
        observatory.save(args.db)

    if args.json:
        payload = results_json[0] if len(results_json) == 1 else results_json
        print(json.dumps(payload, ensure_ascii=False, indent=2))

    return worst_code


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
