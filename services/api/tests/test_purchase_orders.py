from pathlib import Path


def test_purchase_order_workflow_routes_are_registered() -> None:
    source = Path("app/api/routes/purchase_orders.py").read_text()
    router = Path("app/api/router.py").read_text()
    assert '@router.post("")' in source
    assert '@router.post("/{order_id}/approve")' in source
    assert '@router.post("/{order_id}/cancel")' in source
    assert '@router.post("/{order_id}/receive")' in source
    assert 'prefix="/purchase-orders"' in router


def test_purchase_order_receive_requires_approval() -> None:
    source = Path("app/api/routes/purchase_orders.py").read_text()
    assert 'order.status != "approved"' in source
    assert 'Purchase order must be approved before receiving' in source


def test_purchase_order_migration_follows_growth_features() -> None:
    source = Path("alembic/versions/0014_purchase_orders.py").read_text()
    assert 'down_revision: str | None = "0013_growth_features"' in source
