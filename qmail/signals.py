"""Signál = pozorovaný jev, který přispívá komplexní amplitudou do stavu.

Každý detektor (viz :mod:`qmail.detectors`) může "vystřelit" jeden či více
signálů. Signál nese amplitudové příspěvky pro jednotlivé verdikty - včetně
*fáze*, díky níž mohou signály interferovat. Například úspěšná autentizace
přidá k phishingu amplitudu s opačnou fází než podezřelé odkazy, takže se
část phishingové amplitudy vyruší.
"""

from __future__ import annotations

import cmath
from dataclasses import dataclass, field
from typing import Mapping

from .states import BASIS, Verdict


@dataclass(frozen=True)
class Signal:
    """Jeden detekovaný jev s amplitudovými příspěvky do verdiktů.

    Signál má dva kanály:

    * ``contributions`` - komplexní amplitudy přičtené do stavu (mohou
      interferovat podle své fáze),
    * ``damping`` - multiplikativní útlum amplitudy daného verdiktu
      (hodnota < 1 amplitudu tlumí). Modeluje destruktivní vliv, který
      nikdy "nepřestřelí" do velké záporné amplitudy - např. úspěšná
      autentizace potlačí phishingovou amplitudu, ať je jakkoli velká.
    """

    name: str
    detail: str
    contributions: Mapping[Verdict, complex] = field(default_factory=dict)
    damping: Mapping[Verdict, float] = field(default_factory=dict)

    def magnitude(self) -> float:
        """Celková "síla" signálu (norma jeho amplitudového příspěvku)."""
        return cmath.sqrt(
            sum(abs(a) ** 2 for a in self.contributions.values())
        ).real

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "detail": self.detail,
            "contributions": {
                v.label: {"abs": abs(a), "phase": cmath.phase(a)}
                for v, a in self.contributions.items()
            },
            "damping": {v.label: f for v, f in self.damping.items()},
        }


def amp(weight: float, phase: float = 0.0) -> complex:
    """Pomůcka: amplituda dané velikosti a fáze (v radiánech).

    Fáze ``0`` přispívá "kladně", fáze ``pi`` přispívá s opačným znaménkem
    (umožňuje destruktivní interferenci s jinými signály téhož verdiktu).
    """
    return cmath.rect(weight, phase)


def make_signal(
    name: str,
    detail: str,
    *,
    ham: complex = 0j,
    spam: complex = 0j,
    phishing: complex = 0j,
    damp_ham: float = 1.0,
    damp_spam: float = 1.0,
    damp_phishing: float = 1.0,
) -> Signal:
    """Pohodlný konstruktor signálu z pojmenovaných příspěvků."""
    contributions = {
        Verdict.HAM: complex(ham),
        Verdict.SPAM: complex(spam),
        Verdict.PHISHING: complex(phishing),
    }
    # Necháváme jen nenulové, ať je výpis přehledný.
    contributions = {v: a for v, a in contributions.items() if abs(a) > 0}

    damping = {
        Verdict.HAM: damp_ham,
        Verdict.SPAM: damp_spam,
        Verdict.PHISHING: damp_phishing,
    }
    damping = {v: f for v, f in damping.items() if f != 1.0}
    return Signal(name=name, detail=detail, contributions=contributions, damping=damping)


__all__ = ["Signal", "amp", "make_signal", "BASIS"]
