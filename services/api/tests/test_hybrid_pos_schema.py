from app.schemas.identity import BootstrapRequest


def test_hybrid_business_signup():
    payload = BootstrapRequest(
        business_name="Goods and Services",
        business_slug="goods-services",
        pos_type="hybrid",
        branch_name="Main",
        branch_code="MAIN",
        owner_name="Example Person",
        email="example@example.com",
        password="password123",
    )
    assert payload.pos_type == "hybrid"
