from hashlib import sha256
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.config import get_settings
from app.core.database import get_db
from app.models.purchasing import BusinessDocument
from app.schemas.purchasing import DocumentExtractionUpdate
from app.services.object_storage import ObjectStorage, get_object_storage

router = APIRouter()
settings = get_settings()
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}


def _document_dict(document: BusinessDocument, *, duplicate: bool = False) -> dict[str, object]:
    return {
        "id": document.id,
        "branch_id": document.branch_id,
        "document_type": document.document_type,
        "original_filename": document.original_filename,
        "content_type": document.content_type,
        "byte_size": document.byte_size,
        "sha256": document.sha256,
        "processing_status": document.processing_status,
        "extracted_data": document.extracted_data,
        "created_at": document.created_at,
        "duplicate": duplicate,
    }


async def _upload_receipt(
    *,
    document_type: str,
    file: UploadFile,
    context: TenantContext,
    principal: Principal,
    db: AsyncSession,
    storage: ObjectStorage,
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    content_type = (file.content_type or "application/octet-stream").lower()
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="Use JPG, PNG, WEBP or PDF")
    content = await file.read(settings.max_receipt_upload_bytes + 1)
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Receipt file is empty")
    if len(content) > settings.max_receipt_upload_bytes:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Receipt file is too large")

    digest = sha256(content).hexdigest()
    existing_result = await db.execute(
        select(BusinessDocument).where(
            BusinessDocument.tenant_id == context.tenant.id,
            BusinessDocument.sha256 == digest,
        )
    )
    existing = existing_result.scalar_one_or_none()
    if existing is not None:
        return _document_dict(existing, duplicate=True)

    suffix = Path(file.filename or "receipt").suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".pdf"}:
        suffix = ".pdf" if content_type == "application/pdf" else ".bin"
    object_key = f"tenants/{context.tenant.id}/documents/{digest[:2]}/{digest}{suffix}"
    await storage.put_bytes(object_key=object_key, content=content, content_type=content_type)
    document = BusinessDocument(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        document_type=document_type,
        original_filename=(file.filename or "receipt")[:255],
        object_key=object_key,
        content_type=content_type,
        byte_size=len(content),
        sha256=digest,
        processing_status="uploaded",
        captured_by_user_id=principal.user.id,
    )
    try:
        db.add(document)
        await db.commit()
        await db.refresh(document)
        return _document_dict(document)
    except IntegrityError:
        await db.rollback()
        existing_result = await db.execute(
            select(BusinessDocument).where(
                BusinessDocument.tenant_id == context.tenant.id,
                BusinessDocument.sha256 == digest,
            )
        )
        existing = existing_result.scalar_one_or_none()
        if existing is not None:
            return _document_dict(existing, duplicate=True)
        raise


@router.post("/purchase-receipts", status_code=status.HTTP_201_CREATED)
async def upload_purchase_receipt(
    file: UploadFile = File(...),
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
    storage: ObjectStorage = Depends(get_object_storage),
) -> dict[str, object]:
    return await _upload_receipt(
        document_type="purchase_receipt",
        file=file,
        context=context,
        principal=principal,
        db=db,
        storage=storage,
    )


@router.post("/expense-receipts", status_code=status.HTTP_201_CREATED)
async def upload_expense_receipt(
    file: UploadFile = File(...),
    context: TenantContext = Depends(require_permissions("expenses.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
    storage: ObjectStorage = Depends(get_object_storage),
) -> dict[str, object]:
    return await _upload_receipt(
        document_type="expense_receipt",
        file=file,
        context=context,
        principal=principal,
        db=db,
        storage=storage,
    )


@router.get("")
async def list_documents(
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    result = await db.execute(
        select(BusinessDocument)
        .where(BusinessDocument.tenant_id == context.tenant.id)
        .order_by(BusinessDocument.created_at.desc())
        .limit(250)
    )
    return [_document_dict(document) for document in result.scalars().all()]


@router.get("/{document_id}/download-url")
async def document_download_url(
    document_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
    storage: ObjectStorage = Depends(get_object_storage),
) -> dict[str, object]:
    result = await db.execute(
        select(BusinessDocument).where(
            BusinessDocument.id == document_id,
            BusinessDocument.tenant_id == context.tenant.id,
        )
    )
    document = result.scalar_one_or_none()
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    return {
        "document_id": document.id,
        "url": await storage.presigned_get_url(object_key=document.object_key),
        "expires_in": 900,
    }


@router.patch("/{document_id}/extraction")
async def update_document_extraction(
    document_id: UUID,
    payload: DocumentExtractionUpdate,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(BusinessDocument).where(
            BusinessDocument.id == document_id,
            BusinessDocument.tenant_id == context.tenant.id,
        )
    )
    document = result.scalar_one_or_none()
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    document.extracted_data = payload.extracted_data
    document.processing_status = payload.processing_status
    await db.commit()
    await db.refresh(document)
    return _document_dict(document)
