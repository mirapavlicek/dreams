"""Observatoř - paměť minulých měření a role pozorovatele (entanglement).

Kvantová analogie:

* Když nějaký *pozorovatel* změří (zhroutí) e-mail jako závadný, tato znalost
  se neztratí. E-maily, které sdílejí stejné rysy (odesílatel, doména odkazu,
  předmět), jsou s ním *provázané* (entanglement) - jejich prior vlnová funkce
  se posune směrem k dříve naměřenému výsledku. Měření jedné "částice" tak
  informuje o korelovaném stavu druhé (jako v EPR páru).
* Nezávislé potvrzení od *více pozorovatelů* nechá stav rychleji **dekoherovat**
  do klasického, jistého verdiktu - proto roste vliv s počtem různých
  pozorovatelů (faktor sqrt(N)).

Observatoř je tedy sdílená zkušenost: "byl tenhle odesílatel / odkaz / předmět
už dřív - u mě nebo u někoho jiného - označen jako závadný?"
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .parser import ParsedEmail
from .signals import Signal, amp
from .states import BASIS, Verdict

# Kolik amplitudy přidá historie podle typu rysu (sdílený rys = provázanost).
_KEY_BASE: dict[str, float] = {
    "sender": 1.3,
    "replyto": 1.1,
    "url": 1.2,
    "subject": 0.6,
}

# Saturace: kolik vážených hlášení už znamená "skoro jistotu" pro daný rys.
_SCALE = 1.5

# Strop amplitudy z jednoho rysu, ať historie nepřebije veškerou evidenci.
_MAX_KEY_AMP = 2.2

_HUMAN = {
    "sender": "Odesílatel",
    "replyto": "Reply-To doména",
    "url": "Doména odkazu",
    "subject": "Předmět",
}


def _root_domain(host: str) -> str:
    host = host.strip().lower()
    if host.startswith("www."):
        host = host[4:]
    parts = [p for p in host.split(".") if p]
    if len(parts) <= 2:
        return ".".join(parts)
    return ".".join(parts[-2:])


def _subject_fingerprint(subject: str) -> str:
    s = subject.lower()
    s = re.sub(r"^\s*(re|fwd|fw|odp|aw)\s*:\s*", "", s)
    s = re.sub(r"[0-9]+", "#", s)          # čísla nejsou podstatná
    s = re.sub(r"[^a-z#\s]", " ", s)       # pryč interpunkce/diakritika-zbytky
    s = re.sub(r"\s+", " ", s).strip()
    return s[:48]


def feature_keys(mail: ParsedEmail) -> list[str]:
    """Rysy, podle kterých může být e-mail provázán s dřívějšími měřeními."""
    keys: list[str] = []
    if mail.from_domain:
        keys.append(f"sender:{mail.from_domain}")
    if mail.reply_to_domain and mail.reply_to_domain != mail.from_domain:
        keys.append(f"replyto:{mail.reply_to_domain}")
    seen: set[str] = set()
    for d in mail.url_domains:
        root = _root_domain(d)
        if root and root not in seen:
            seen.add(root)
            keys.append(f"url:{root}")
    fp = _subject_fingerprint(mail.subject)
    if len(fp) >= 4:
        keys.append(f"subject:{fp}")
    return keys


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class KeyRecord:
    """Agregovaná pozorování pro jeden rys (klíč)."""

    verdict_weight: dict[str, float] = field(default_factory=dict)
    observers: list[str] = field(default_factory=list)
    reports: int = 0
    first_seen: str = ""
    last_seen: str = ""

    def add(self, verdict: Verdict, observer: str, weight: float, ts: str) -> None:
        self.verdict_weight[verdict.label] = (
            self.verdict_weight.get(verdict.label, 0.0) + weight
        )
        if observer not in self.observers:
            self.observers.append(observer)
        self.reports += 1
        if not self.first_seen:
            self.first_seen = ts
        self.last_seen = ts

    def to_dict(self) -> dict:
        return {
            "verdict_weight": self.verdict_weight,
            "observers": self.observers,
            "reports": self.reports,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "KeyRecord":
        return cls(
            verdict_weight={k: float(v) for k, v in d.get("verdict_weight", {}).items()},
            observers=list(d.get("observers", [])),
            reports=int(d.get("reports", 0)),
            first_seen=d.get("first_seen", ""),
            last_seen=d.get("last_seen", ""),
        )


def _verdict_by_label(label: str) -> Verdict | None:
    for v in BASIS:
        if v.label == label:
            return v
    return None


class Observatory:
    """Trvalá paměť měření napříč e-maily a pozorovateli."""

    def __init__(self, records: dict[str, KeyRecord] | None = None) -> None:
        self.records: dict[str, KeyRecord] = records or {}

    # -- záznam ----------------------------------------------------------

    def record(
        self,
        mail: ParsedEmail,
        verdict: Verdict,
        observer: str = "local",
        weight: float = 1.0,
        ts: str | None = None,
    ) -> list[str]:
        """Zaznamená měření e-mailu pod všechny jeho rysy.

        Tím se e-mail (resp. jeho rysy) "provážou" s tímto verdiktem a ovlivní
        prior u budoucích e-mailů, které stejný rys sdílejí.
        """
        ts = ts or _now_iso()
        keys = feature_keys(mail)
        for key in keys:
            rec = self.records.setdefault(key, KeyRecord())
            rec.add(verdict, observer, weight, ts)
        return keys

    # -- vliv na prior (historie -> signály) -----------------------------

    def signals_for(self, mail: ParsedEmail) -> list[Signal]:
        """Vyrobí signály z dřívějších pozorování shodných rysů.

        Tyto signály vstupují do superpozice stejně jako detektory - jen
        nesou "kolektivní paměť" pozorovatelů místo obsahu aktuálního e-mailu.
        """
        signals: list[Signal] = []
        for key in feature_keys(mail):
            rec = self.records.get(key)
            if not rec or rec.reports == 0:
                continue
            keytype, _, value = key.partition(":")
            base = _KEY_BASE.get(keytype, 0.6)
            n_obs = max(1, len(rec.observers))
            obs_factor = math.sqrt(n_obs)

            contributions: dict[Verdict, complex] = {}
            for label, w in rec.verdict_weight.items():
                verdict = _verdict_by_label(label)
                if verdict is None or w <= 0:
                    continue
                mag = min(_MAX_KEY_AMP, base * math.tanh(w / _SCALE) * obs_factor)
                if mag > 0:
                    contributions[verdict] = amp(mag)
            if not contributions:
                continue

            dominant = max(rec.verdict_weight, key=rec.verdict_weight.get)
            others = "" if n_obs == 1 else f", {n_obs} nezávislých pozorovatelů"
            detail = (
                f"{_HUMAN.get(keytype, keytype)} '{value}' byl dříve {rec.reports}x "
                f"měřen (převážně: {dominant}{others}) - provázáno historií"
            )
            signals.append(Signal(
                name=f"history_{keytype}",
                detail=detail,
                contributions=contributions,
            ))
        return signals

    def known_keys(self, mail: ParsedEmail) -> list[str]:
        """Které rysy aktuálního e-mailu už observatoř zná."""
        return [k for k in feature_keys(mail) if k in self.records]

    # -- perzistence -----------------------------------------------------

    def to_dict(self) -> dict:
        return {
            "version": 1,
            "records": {k: r.to_dict() for k, r in self.records.items()},
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Observatory":
        records = {
            k: KeyRecord.from_dict(v) for k, v in d.get("records", {}).items()
        }
        return cls(records)

    def save(self, path: str | Path) -> None:
        Path(path).write_text(
            json.dumps(self.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @classmethod
    def load(cls, path: str | Path) -> "Observatory":
        p = Path(path)
        if not p.exists():
            return cls()
        return cls.from_dict(json.loads(p.read_text(encoding="utf-8")))

    def __len__(self) -> int:
        return len(self.records)
