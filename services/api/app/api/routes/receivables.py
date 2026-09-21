from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.services.receivables import receivables_health

router = APIRouter()


@router.get("/reconciliation")
async def get_receivables_reconciliation(
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await receivables_health(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
    )
