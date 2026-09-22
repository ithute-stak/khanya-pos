from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.services.management_reports import cash_flow_statement

router = APIRouter()


@router.get("/cash-flow")
async def get_cash_flow_statement(
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if start is not None and end is not None and end < start:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end must not be before start",
        )
    return await cash_flow_statement(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
        start=start,
        end=end,
    )
