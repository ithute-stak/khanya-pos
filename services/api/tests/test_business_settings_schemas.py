from uuid import uuid4

from app.schemas.identity import BranchSummary, BranchUpdate, TenantUpdate


def test_branch_summary_includes_active_state() -> None:
    summary = BranchSummary(
        id=uuid4(),
        name="Maseru Central",
        code="MSU",
        location="Maseru",
        is_main=True,
        is_active=True,
    )
    assert summary.is_active is True
    assert summary.is_main is True


def test_business_and_branch_updates_normalize_through_schema() -> None:
    tenant = TenantUpdate(name="Khanya Resources Pty Ltd")
    branch = BranchUpdate(
        name="Mafeteng",
        code="MFT",
        location="Mafeteng",
        is_main=False,
        is_active=True,
    )
    assert tenant.name == "Khanya Resources Pty Ltd"
    assert branch.code == "MFT"
