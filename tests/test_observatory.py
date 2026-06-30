import pytest

from qmail import Observatory, screen_raw
from qmail.observatory import feature_keys
from qmail.parser import parse_email
from qmail.states import Verdict

# Neutrální e-mail bez obsahových signálů - izoluje vliv historie.
CLEAN = (
    "From: Sales <info@nove-neznama.tld>\n"
    "To: user@example.com\n"
    "Subject: Nabidka spoluprace\n"
    "Content-Type: text/plain\n\n"
    "Dobry den, radi bychom vam predstavili nasi nabidku. S pozdravem.\n"
)


def _mail(raw=CLEAN):
    return parse_email(raw)


def test_baseline_clean_has_no_content_signals():
    result = screen_raw(CLEAN)
    assert result.signals == []
    assert result.verdict is Verdict.HAM


def test_feature_keys_extracted():
    keys = feature_keys(_mail())
    assert any(k.startswith("sender:nove-neznama.tld") for k in keys)
    assert any(k.startswith("subject:") for k in keys)


def test_prior_observation_shifts_toward_phishing():
    obs = Observatory()
    baseline = screen_raw(CLEAN, observatory=obs)

    # Jiný pozorovatel dříve označil tohoto odesílatele za phishing.
    obs.record(_mail(), Verdict.PHISHING, observer="partner-feed")
    influenced = screen_raw(CLEAN, observatory=obs)

    assert influenced.probabilities[Verdict.PHISHING] > baseline.probabilities[Verdict.PHISHING]
    assert influenced.influenced_by_history
    assert any(s.name == "history_sender" for s in influenced.history_signals)


def test_more_observers_increase_confidence():
    one = Observatory()
    one.record(_mail(), Verdict.PHISHING, observer="a")
    r_one = screen_raw(CLEAN, observatory=one)

    many = Observatory()
    for who in ("a", "b", "c", "d"):
        many.record(_mail(), Verdict.PHISHING, observer=who)
    r_many = screen_raw(CLEAN, observatory=many)

    # Nezávislé potvrzení od více pozorovatelů -> jistější (vyšší) phishing.
    assert r_many.probabilities[Verdict.PHISHING] > r_one.probabilities[Verdict.PHISHING]


def test_ham_reputation_boosts_ham():
    obs = Observatory()
    for who in ("a", "b", "c"):
        obs.record(_mail(), Verdict.HAM, observer=who)
    result = screen_raw(CLEAN, observatory=obs)
    assert result.verdict is Verdict.HAM
    assert result.probabilities[Verdict.HAM] >= screen_raw(CLEAN).probabilities[Verdict.HAM]


def test_history_can_flip_clean_email_to_threat():
    obs = Observatory()
    for who in ("a", "b", "c"):
        obs.record(_mail(), Verdict.PHISHING, observer=who, weight=2.0)
    result = screen_raw(CLEAN, observatory=obs)
    assert result.verdict is Verdict.PHISHING


def test_shared_url_domain_links_emails():
    obs = Observatory()
    bad = (
        "From: a@a.tld\nTo: b@b.tld\nSubject: hi\n\n"
        "see http://shared-bad-domain.tld/x\n"
    )
    obs.record(parse_email(bad), Verdict.PHISHING, observer="feed")

    # Jiný e-mail od jiného odesílatele, ale se stejnou doménou odkazu.
    other = (
        "From: c@c.tld\nTo: d@d.tld\nSubject: ahoj\n\n"
        "odkaz http://shared-bad-domain.tld/y\n"
    )
    result = screen_raw(other, observatory=obs)
    assert any(s.name == "history_url" for s in result.history_signals)


def test_persistence_roundtrip(tmp_path):
    obs = Observatory()
    obs.record(_mail(), Verdict.PHISHING, observer="x")
    path = tmp_path / "obs.json"
    obs.save(path)

    loaded = Observatory.load(path)
    assert len(loaded) == len(obs)
    result = screen_raw(CLEAN, observatory=loaded)
    assert result.influenced_by_history


def test_load_missing_file_is_empty(tmp_path):
    loaded = Observatory.load(tmp_path / "does-not-exist.json")
    assert len(loaded) == 0


def test_subject_fingerprint_ignores_reply_prefix_and_numbers():
    k1 = feature_keys(parse_email("From: a@a.tld\nSubject: Faktura 12345\n\nx"))
    k2 = feature_keys(parse_email("From: a@a.tld\nSubject: Re: Faktura 99\n\nx"))
    subj1 = [k for k in k1 if k.startswith("subject:")][0]
    subj2 = [k for k in k2 if k.startswith("subject:")][0]
    assert subj1 == subj2
