from datetime import datetime, timezone

from app.api.routes.reports import _window


def test_report_window_defaults_to_recent_period():
    start, end = _window(None, None)
    assert start.tzinfo is not None
    assert end.tzinfo is not None
    assert end > start
    assert (end - start).days == 30


def test_report_window_normalizes_naive_dates_to_utc():
    start, end = _window(datetime(2026, 9, 1), datetime(2026, 9, 2))
    assert start.tzinfo == timezone.utc
    assert end.tzinfo == timezone.utc
