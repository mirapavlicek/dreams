"""Příkazová řádka: ``python -m qmail soubor.eml`` nebo přes stdin.

Vypíše kvantový verdikt: pravděpodobnosti |psi|^2 jednotlivých stavů,
neurčitost (entropii), seznam signálů a finální kolaps.
"""

from __future__ import annotations

import argparse
import json
import sys

from .screen import ScreenResult, screen_raw
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


def _render_text(result: ScreenResult, color: bool) -> str:
    lines: list[str] = []
    lines.append("=" * 56)
    lines.append("KVANTOVÁ KONTROLA E-MAILU (|psi|^2)")
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

    if result.signals:
        lines.append(f"Detekované signály ({len(result.signals)}):")
        for s in result.signals:
            contrib = ", ".join(
                f"{v.label} {abs(a):.2f}" + ("(-)" if abs(a) > 0 and a.real < 0 else "")
                for v, a in s.contributions.items()
            )
            lines.append(f"  - [{s.name}] {s.detail}")
            if contrib:
                lines.append(f"      amplitudy: {contrib}")
    else:
        lines.append("Žádné podezřelé signály - stav zůstal blízko prior |ham>.")
    lines.append("=" * 56)
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="qmail",
        description="Kvantově inspirovaná kontrola e-mailů proti phishingu a spamu.",
    )
    parser.add_argument(
        "path",
        nargs="?",
        help="Cesta k .eml souboru. Bez ní se čte ze stdin.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Výstup ve formátu JSON.",
    )
    parser.add_argument(
        "--shots", type=int, default=0,
        help="Provede N pravděpodobnostních měření a vypíše empirické rozdělení.",
    )
    parser.add_argument(
        "--no-color", action="store_true", help="Vypne barevný výstup.",
    )
    args = parser.parse_args(argv)

    if args.path:
        with open(args.path, "rb") as fh:
            raw = fh.read()
    else:
        raw = sys.stdin.buffer.read()

    result = screen_raw(raw)

    if args.json:
        out = result.as_dict()
        if args.shots > 0:
            out["sampled"] = {
                v.label: p for v, p in result.sample_distribution(args.shots, seed=0).items()
            }
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        color = sys.stdout.isatty() and not args.no_color
        print(_render_text(result, color=color))
        if args.shots > 0:
            sampled = result.sample_distribution(args.shots, seed=0)
            print(f"\n{args.shots}x měření (empirický kolaps):")
            for v in BASIS:
                print(f"  {v.label:<11} {sampled[v]:6.1%}")

    return 0 if result.verdict == Verdict.HAM else 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
