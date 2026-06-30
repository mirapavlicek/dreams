import pathlib

import pytest

from qmail import screen_raw
from qmail.states import Verdict

EXAMPLES = pathlib.Path(__file__).resolve().parent.parent / "examples"


def _load(name: str) -> str:
    return (EXAMPLES / name).read_text(encoding="utf-8")


def test_legit_email_collapses_to_ham():
    result = screen_raw(_load("legit.eml"))
    assert result.verdict is Verdict.HAM
    assert result.confidence > 0.5
    assert not result.is_threat


def test_spam_email_collapses_to_spam():
    result = screen_raw(_load("spam.eml"))
    assert result.verdict is Verdict.SPAM
    assert result.is_threat
    # spam by měl dominovat nad phishingem
    assert result.probabilities[Verdict.SPAM] > result.probabilities[Verdict.PHISHING]


def test_phishing_email_collapses_to_phishing():
    result = screen_raw(_load("phishing.eml"))
    assert result.verdict is Verdict.PHISHING
    assert result.is_threat
    assert result.probabilities[Verdict.PHISHING] > 0.5


def test_authentication_pass_interferes_with_phishing():
    # Stejné podezřelé tělo, ale s úspěšnou autentizací a shodným odesílatelem
    # -> phishingová amplituda je interferencí potlačena.
    base_headers = (
        "From: Info <info@firma.cz>\n"
        "To: user@example.com\n"
        "Subject: Faktura\n"
    )
    body = "\nContent-Type: text/plain\n\nDobry den, posilam fakturu v priloze.\n"

    no_auth = screen_raw(base_headers + body)
    with_auth = screen_raw(
        base_headers
        + "Authentication-Results: mx; spf=pass; dkim=pass; dmarc=pass\n"
        + body
    )
    assert with_auth.probabilities[Verdict.PHISHING] <= no_auth.probabilities[Verdict.PHISHING]
    assert with_auth.probabilities[Verdict.HAM] >= no_auth.probabilities[Verdict.HAM]


def test_display_name_spoof_detected():
    raw = (
        "From: PayPal Support <random@gmail.com>\n"
        "To: user@example.com\n"
        "Subject: hello\n\n"
        "Body text.\n"
    )
    result = screen_raw(raw)
    names = {s.name for s in result.signals}
    assert "display_name_spoof" in names


def test_anchor_mismatch_detected():
    raw = (
        "From: Bank <info@bank.example>\n"
        "To: user@example.com\n"
        "Subject: notice\n"
        "Content-Type: text/html\n\n"
        '<html><body><a href="http://evil-host.ru/login">www.bank.example</a></body></html>\n'
    )
    result = screen_raw(raw)
    names = {s.name for s in result.signals}
    assert "anchor_mismatch" in names


def test_ip_url_flagged_as_phishing_signal():
    raw = (
        "From: x <x@x.com>\nTo: y@y.com\nSubject: s\n\n"
        "Please visit http://203.0.113.9/login now.\n"
    )
    result = screen_raw(raw)
    names = {s.name for s in result.signals}
    assert "ip_url" in names


def test_result_as_dict_roundtrip():
    result = screen_raw(_load("phishing.eml"))
    d = result.as_dict()
    assert d["verdict"] == "phishing"
    assert pytest.approx(sum(d["probabilities"].values()), abs=1e-6) == 1.0
    assert isinstance(d["signals"], list) and d["signals"]


def test_sampling_matches_probabilities():
    result = screen_raw(_load("spam.eml"))
    sampled = result.sample_distribution(shots=2000, seed=1)
    # Empirické rozdělení by mělo zhruba odpovídat |psi|^2.
    for v in result.probabilities:
        assert abs(sampled[v] - result.probabilities[v]) < 0.08
