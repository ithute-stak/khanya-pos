from pathlib import Path

from app.api.routes.reports import _ratio_score, _score


def test_score_is_clamped() -> None:
    assert _score(-5) == 0
    assert _score(45.4) == 45
    assert _score(101) == 100


def test_ratio_score_rewards_low_pressure() -> None:
    assert _ratio_score(0, healthy_at=0.1, bad_at=0.6) == 100
    assert _ratio_score(0.6, healthy_at=0.1, bad_at=0.6) == 0
    assert 0 < _ratio_score(0.35, healthy_at=0.1, bad_at=0.6) < 100


def test_business_intelligence_routes_are_exposed() -> None:
    source = Path('app/api/routes/reports.py').read_text()
    assert '@router.get("/business-health")' in source
    assert '@router.get("/stock-intelligence")' in source
    assert '@router.get("/supplier-intelligence")' in source
