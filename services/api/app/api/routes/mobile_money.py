"""Read-only visibility into unresolved collection intents for authorized staff.

No POST endpoints or client-driven payment status updates are exposed. Pending
and unknown records do not mean money was received.
"""

from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.services.mobile_money_review_queue import list_unresolved_collections

router = APIRouter()


class UnresolvedCollectionView(BaseModel):
    operation_id: UUID
    rail: str
    amount: Decimal
    currency: str
    status: str

    # A provider reference and PII are intentionally not returned here.


@router.get("/unresolved", response_model=list[UnresolvedCollectionView])
async def get_unresolved_mobile_money(
    minimum_age_minutes: int = Query(default=5, ge=0, le=10080),
    limit: int = Query(default=100, ge=1, le=200),
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[UnresolvedCollectionView]:
    if context.branch is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Branch-ID is required",
        )
    records = await list_unresolved_collections(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        minimum_age=timedelta(minutes=minimum_age_minutes),
        limit=limit,
    )
    return [
        UnresolvedCollectionView(
            operation_id=record.operation_id,
            rail=record.rail,
            amount=record.amount,
            currency=record.currency,
            status=record.status,
        )
        for record in records
    ]
