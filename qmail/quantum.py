"""Kvantové jádro: stavový vektor, normalizace, |psi|^2 a kolaps měřením.

Implementováno čistě nad standardní knihovnou (``complex``, ``cmath``,
``math``, ``random``), aby modul běžel kdekoli bez externích závislostí.
"""

from __future__ import annotations

import cmath
import math
import random
from dataclasses import dataclass, field
from typing import Iterable, Mapping, Sequence

from .states import BASIS, Verdict

# Numerická tolerance pro detekci "nulového" vektoru.
_EPS = 1e-12


@dataclass
class QuantumState:
    """Diskrétní vlnová funkce nad bází verdiktů.

    Drží komplexní amplitudu pro každý bázový stav. Pravděpodobnost stavu
    je druhá mocnina velikosti amplitudy (Bornovo pravidlo), stejně jako
    |psi(x)|^2 udává hustotu pravděpodobnosti polohy elektronu.
    """

    amplitudes: list[complex] = field(
        default_factory=lambda: [0j for _ in BASIS]
    )

    def __post_init__(self) -> None:
        if len(self.amplitudes) != len(BASIS):
            raise ValueError(
                f"Stavový vektor musí mít {len(BASIS)} složek, "
                f"dostal {len(self.amplitudes)}."
            )
        self.amplitudes = [complex(a) for a in self.amplitudes]

    # -- konstruktory ----------------------------------------------------

    @classmethod
    def basis(cls, verdict: Verdict) -> "QuantumState":
        """Čistý bázový stav (např. |phishing>)."""
        amps = [0j for _ in BASIS]
        amps[int(verdict)] = 1 + 0j
        return cls(amps)

    @classmethod
    def uniform(cls) -> "QuantumState":
        """Maximální superpozice - všechny verdikty stejně pravděpodobné."""
        a = 1 / math.sqrt(len(BASIS))
        return cls([complex(a) for _ in BASIS]).normalized()

    @classmethod
    def from_mapping(cls, mapping: Mapping[Verdict, complex]) -> "QuantumState":
        amps = [0j for _ in BASIS]
        for verdict, amp in mapping.items():
            amps[int(verdict)] = complex(amp)
        return cls(amps)

    # -- algebra ---------------------------------------------------------

    def add(self, contribution: Mapping[Verdict, complex] | Sequence[complex]) -> "QuantumState":
        """Vrátí nový stav s přičtenou amplitudovou kontribucí.

        Sčítání probíhá v *amplitudovém* prostoru, takže se příspěvky
        mohou navzájem zesilovat (konstruktivní interference) i rušit
        (destruktivní interference) podle své fáze.
        """
        amps = list(self.amplitudes)
        if isinstance(contribution, Mapping):
            for verdict, amp in contribution.items():
                amps[int(verdict)] += complex(amp)
        else:
            if len(contribution) != len(BASIS):
                raise ValueError("Kontribuce má špatný počet složek.")
            for i, amp in enumerate(contribution):
                amps[i] += complex(amp)
        return QuantumState(amps)

    def damp(self, factors: Mapping[Verdict, float]) -> "QuantumState":
        """Vrátí nový stav s multiplikativně utlumenými amplitudami.

        Faktor < 1 amplitudu daného stavu tlumí (destruktivní vliv, který
        ale nepřestřelí do velké záporné amplitudy), faktor > 1 ji zesiluje.
        """
        amps = list(self.amplitudes)
        for verdict, factor in factors.items():
            amps[int(verdict)] *= factor
        return QuantumState(amps)

    def norm(self) -> float:
        """Eukleidovská norma stavového vektoru (před normalizací)."""
        return math.sqrt(sum(abs(a) ** 2 for a in self.amplitudes))

    def normalized(self) -> "QuantumState":
        """Vrátí stav s jednotkovou normou (sum |amp|^2 == 1).

        Je-li vektor prakticky nulový, vrací maximální superpozici - to
        odpovídá situaci "žádná informace", kdy je výsledek zcela neurčitý.
        """
        n = self.norm()
        if n < _EPS:
            a = 1 / math.sqrt(len(BASIS))
            return QuantumState([complex(a) for _ in BASIS])
        return QuantumState([a / n for a in self.amplitudes])

    # -- měření ----------------------------------------------------------

    def probabilities(self) -> dict[Verdict, float]:
        """Bornovo pravidlo: P(stav) = |amplituda|^2 (na normalizovaném stavu)."""
        state = self.normalized()
        return {v: abs(state.amplitudes[int(v)]) ** 2 for v in BASIS}

    def collapse(self) -> Verdict:
        """Deterministické měření - nejpravděpodobnější výsledek (argmax |psi|^2).

        Toto používáme pro skutečné rozhodnutí: vektor "zhroutíme" do
        verdiktu s nejvyšší hustotou pravděpodobnosti.
        """
        probs = self.probabilities()
        return max(BASIS, key=lambda v: probs[v])

    def measure(self, rng: random.Random | None = None) -> Verdict:
        """Pravděpodobnostní měření - náhodný kolaps podle |psi|^2.

        Modeluje skutečné kvantové měření: opakovaná měření identického
        stavu dají různé výsledky s četností danou |psi|^2. Užitečné pro
        Monte Carlo a demonstraci nedeterminismu.
        """
        rng = rng or random
        probs = self.probabilities()
        r = rng.random()
        cumulative = 0.0
        for v in BASIS:
            cumulative += probs[v]
            if r <= cumulative:
                return v
        return BASIS[-1]

    # -- míry neurčitosti ------------------------------------------------

    def entropy(self) -> float:
        """Shannonova entropie rozdělení |psi|^2, normalizovaná do [0, 1].

        Vysoká hodnota = stav je "rozmazaný" přes více verdiktů (silná
        superpozice, špatně lokalizovaný), tj. analogie velké neurčitosti
        polohy. Nízká hodnota = stav je ostře lokalizovaný v jednom verdiktu.
        """
        probs = self.probabilities().values()
        h = -sum(p * math.log(p) for p in probs if p > _EPS)
        return h / math.log(len(BASIS))

    def purity(self) -> float:
        """Čistota stavu = sum p^2 v [1/N, 1].

        1.0 znamená čistý stav (jistý verdikt), 1/N maximální směs.
        """
        return sum(p ** 2 for p in self.probabilities().values())

    def is_decided(self, confidence: float = 0.5, max_entropy: float = 0.85) -> bool:
        """Je stav dost lokalizovaný, aby se dal brát jako jistý verdikt?

        Vyžaduje současně dostatečně vysokou špičkovou pravděpodobnost
        i dostatečně nízkou entropii (analogie ostře lokalizované polohy).
        """
        probs = self.probabilities()
        top = max(probs.values())
        return top >= confidence and self.entropy() <= max_entropy

    # -- pomocné ---------------------------------------------------------

    @staticmethod
    def superpose(states: Iterable["QuantumState"]) -> "QuantumState":
        """Lineární superpozice více stavů (součet amplitud, pak normalizace)."""
        total = QuantumState()
        for s in states:
            total = total.add(s.amplitudes)
        return total.normalized()

    def phase(self, verdict: Verdict) -> float:
        """Fáze amplitudy daného stavu v radiánech (kvůli interferenci)."""
        return cmath.phase(self.amplitudes[int(verdict)])

    def __repr__(self) -> str:  # pragma: no cover - jen pro ladění
        probs = self.probabilities()
        parts = ", ".join(f"{v.label}={probs[v]:.3f}" for v in BASIS)
        return f"QuantumState({parts}, H={self.entropy():.3f})"
