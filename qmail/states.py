"""Základní (bázové) stavy, do kterých se e-mail "měří".

V kvantové mechanice měříme polohu v nějaké bázi vlastních stavů operátoru.
Zde je bází trojice vzájemně se vylučujících verdiktů.
"""

from __future__ import annotations

from enum import IntEnum


class Verdict(IntEnum):
    """Bázové stavy systému (eigenstates pozorovatelné veličiny "verdikt").

    Pořadí (index) je důležité - používá se jako index do amplitudového
    vektoru ve :class:`qmail.quantum.QuantumState`.
    """

    HAM = 0       # legitimní, žádaná pošta
    SPAM = 1      # nevyžádaná reklama / hromadná pošta
    PHISHING = 2  # pokus o krádež údajů / podvod

    @property
    def label(self) -> str:
        return {
            Verdict.HAM: "legitimní",
            Verdict.SPAM: "spam",
            Verdict.PHISHING: "phishing",
        }[self]


#: Stabilní pořadí stavů pro iteraci a indexaci amplitud.
BASIS: tuple[Verdict, ...] = (Verdict.HAM, Verdict.SPAM, Verdict.PHISHING)
