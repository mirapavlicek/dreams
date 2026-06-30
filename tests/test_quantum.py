import math

import pytest

from qmail.quantum import QuantumState
from qmail.signals import amp
from qmail.states import BASIS, Verdict


def test_basis_state_is_pure():
    s = QuantumState.basis(Verdict.PHISHING)
    probs = s.probabilities()
    assert probs[Verdict.PHISHING] == pytest.approx(1.0)
    assert probs[Verdict.HAM] == pytest.approx(0.0)
    assert s.entropy() == pytest.approx(0.0)
    assert s.purity() == pytest.approx(1.0)
    assert s.collapse() is Verdict.PHISHING


def test_uniform_state_is_max_uncertain():
    s = QuantumState.uniform()
    for v in BASIS:
        assert s.probabilities()[v] == pytest.approx(1 / len(BASIS))
    assert s.entropy() == pytest.approx(1.0)


def test_probabilities_sum_to_one():
    s = QuantumState.from_mapping({
        Verdict.HAM: 0.7 + 0.2j,
        Verdict.SPAM: 1.1,
        Verdict.PHISHING: 0.3j,
    })
    assert sum(s.probabilities().values()) == pytest.approx(1.0)


def test_born_rule_squares_amplitude():
    # amplituda 3 a 4 -> pravděpodobnosti 9/25 a 16/25.
    s = QuantumState.from_mapping({Verdict.HAM: 3, Verdict.SPAM: 4})
    probs = s.probabilities()
    assert probs[Verdict.HAM] == pytest.approx(9 / 25)
    assert probs[Verdict.SPAM] == pytest.approx(16 / 25)


def test_destructive_interference_cancels_amplitude():
    # Dvě amplitudy stejné velikosti a opačné fáze (0 a pi) se vyruší.
    s = QuantumState()
    s = s.add({Verdict.PHISHING: amp(1.0, 0.0)})
    s = s.add({Verdict.PHISHING: amp(1.0, math.pi)})
    s = s.add({Verdict.HAM: amp(1.0)})
    probs = s.probabilities()
    assert probs[Verdict.PHISHING] == pytest.approx(0.0, abs=1e-9)
    assert probs[Verdict.HAM] == pytest.approx(1.0, abs=1e-9)


def test_constructive_interference_adds_amplitude():
    s = QuantumState()
    s = s.add({Verdict.SPAM: amp(0.5)})
    s = s.add({Verdict.SPAM: amp(0.5)})
    # |0.5 + 0.5|^2 = 1 (před normalizací jediná složka -> p=1).
    assert s.probabilities()[Verdict.SPAM] == pytest.approx(1.0)


def test_normalized_zero_vector_is_uniform():
    s = QuantumState().normalized()
    assert s.probabilities()[Verdict.HAM] == pytest.approx(1 / len(BASIS))


def test_measure_follows_distribution():
    import random
    s = QuantumState.from_mapping({Verdict.HAM: 1.0, Verdict.SPAM: 1.0})
    rng = random.Random(42)
    counts = {Verdict.HAM: 0, Verdict.SPAM: 0, Verdict.PHISHING: 0}
    for _ in range(4000):
        counts[s.measure(rng)] += 1
    # Očekáváme zhruba 50/50 mezi HAM a SPAM.
    assert abs(counts[Verdict.HAM] - counts[Verdict.SPAM]) < 400
    assert counts[Verdict.PHISHING] == 0


def test_wrong_length_raises():
    with pytest.raises(ValueError):
        QuantumState([1 + 0j, 0j])
