"""Vysokoúrovňové API: ze surového e-mailu vyrob kvantový verdikt.

Postup (analogie s určováním polohy elektronu):
1. prior = výchozí vlnová funkce (systém začíná blízko stavu |ham>),
2. každý detekovaný jev přidá komplexní amplitudu (interference),
3. stav se normalizuje -> |psi|^2 dá hustotu pravděpodobnosti verdiktů,
4. *kolaps* (argmax |psi|^2) určí finální verdikt,
5. entropie říká, jak je stav "lokalizovaný" (jistý) vs. "rozmazaný".
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

from typing import TYPE_CHECKING

from .detectors import run_detectors
from .parser import ParsedEmail, parse_email
from .quantum import QuantumState
from .signals import Signal, amp
from .states import BASIS, Verdict

if TYPE_CHECKING:  # pragma: no cover
    from .observatory import Observatory

#: Výchozí prior - systém startuje s důvěrou ve stav |ham>, ale s nenulovou
#: baseline amplitudou ostatních verdiktů (nikdy nejsme absolutně jistí).
DEFAULT_PRIOR = QuantumState.from_mapping({
    Verdict.HAM: amp(1.0),
    Verdict.SPAM: amp(0.18),
    Verdict.PHISHING: amp(0.12),
})


@dataclass
class ScreenResult:
    """Výsledek kvantové kontroly e-mailu."""

    state: QuantumState
    signals: list[Signal]
    history_signals: list[Signal] = field(default_factory=list)
    verdict: Verdict = field(init=False)
    probabilities: dict[Verdict, float] = field(init=False)
    uncertainty: float = field(init=False)
    purity: float = field(init=False)

    def __post_init__(self) -> None:
        self.probabilities = self.state.probabilities()
        self.verdict = self.state.collapse()
        self.uncertainty = self.state.entropy()
        self.purity = self.state.purity()

    @property
    def confidence(self) -> float:
        """Pravděpodobnost vítězného verdiktu (špička |psi|^2)."""
        return self.probabilities[self.verdict]

    @property
    def needs_review(self) -> bool:
        """Je stav příliš "rozmazaný" na jednoznačné rozhodnutí?

        Analogie: polohu nelze ostře určit, dokud je vlnová funkce
        rozprostřená přes více stavů.
        """
        return not self.state.is_decided()

    @property
    def is_threat(self) -> bool:
        return self.verdict in (Verdict.SPAM, Verdict.PHISHING)

    @property
    def influenced_by_history(self) -> bool:
        """Ovlivnila verdikt kolektivní paměť pozorovatelů?"""
        return bool(self.history_signals)

    def measure(self, rng: random.Random | None = None) -> Verdict:
        """Jedno pravděpodobnostní měření (náhodný kolaps podle |psi|^2)."""
        return self.state.measure(rng)

    def sample_distribution(self, shots: int = 1000, seed: int | None = None) -> dict[Verdict, float]:
        """Empirické rozdělení z opakovaných měření (jako experiment se 'shots')."""
        rng = random.Random(seed)
        counts = {v: 0 for v in BASIS}
        for _ in range(shots):
            counts[self.state.measure(rng)] += 1
        return {v: counts[v] / shots for v in BASIS}

    def as_dict(self) -> dict:
        return {
            "verdict": self.verdict.label,
            "confidence": self.confidence,
            "uncertainty": self.uncertainty,
            "purity": self.purity,
            "needs_review": self.needs_review,
            "is_threat": self.is_threat,
            "influenced_by_history": self.influenced_by_history,
            "probabilities": {v.label: p for v, p in self.probabilities.items()},
            "signals": [s.as_dict() for s in self.signals],
            "history_signals": [s.as_dict() for s in self.history_signals],
        }


def screen_email(
    mail: ParsedEmail,
    prior: QuantumState | None = None,
    observatory: "Observatory | None" = None,
) -> ScreenResult:
    """Provede kvantovou kontrolu nad již rozparsovaným e-mailem.

    Je-li předána ``observatory``, vstoupí do superpozice i "history" signály
    z dřívějších měření shodných rysů (role pozorovatele / entanglement).
    """
    state = prior or DEFAULT_PRIOR
    content_signals = run_detectors(mail)
    history_signals = observatory.signals_for(mail) if observatory else []
    # Historie tvoří prior znalost - dáme ji na začátek, pak obsahové signály.
    signals = history_signals + content_signals

    # 1) Nejprve sečteme všechny amplitudové příspěvky (interference).
    for signal in signals:
        if signal.contributions:
            state = state.add(signal.contributions)
    # 2) Poté aplikujeme útlum (např. autentizace potlačí naakumulovanou
    #    phishingovou/spamovou amplitudu - destruktivní vliv bez přestřelení).
    for signal in signals:
        if signal.damping:
            state = state.damp(signal.damping)
    return ScreenResult(
        state=state.normalized(),
        signals=signals,
        history_signals=history_signals,
    )


def screen_raw(
    raw: str | bytes,
    prior: QuantumState | None = None,
    observatory: "Observatory | None" = None,
) -> ScreenResult:
    """Provede kvantovou kontrolu nad surovým e-mailem (.eml text/bajty)."""
    return screen_email(parse_email(raw), prior=prior, observatory=observatory)
