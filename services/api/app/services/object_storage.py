import asyncio
from functools import lru_cache

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

from app.core.config import get_settings


class ObjectStorage:
    def __init__(self) -> None:
        settings = get_settings()
        self.bucket = settings.object_storage_bucket
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.object_storage_endpoint,
            aws_access_key_id=settings.object_storage_access_key,
            aws_secret_access_key=settings.object_storage_secret_key,
            region_name=settings.object_storage_region,
            config=Config(signature_version="s3v4"),
        )

    def _ensure_bucket_sync(self) -> None:
        try:
            self._client.head_bucket(Bucket=self.bucket)
        except ClientError:
            self._client.create_bucket(Bucket=self.bucket)

    async def put_bytes(self, *, object_key: str, content: bytes, content_type: str) -> None:
        def write() -> None:
            self._ensure_bucket_sync()
            self._client.put_object(
                Bucket=self.bucket,
                Key=object_key,
                Body=content,
                ContentType=content_type,
            )

        await asyncio.to_thread(write)

    async def presigned_get_url(self, *, object_key: str, expires_seconds: int = 900) -> str:
        def sign() -> str:
            self._ensure_bucket_sync()
            return self._client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self.bucket, "Key": object_key},
                ExpiresIn=expires_seconds,
            )

        return await asyncio.to_thread(sign)


@lru_cache
def get_object_storage() -> ObjectStorage:
    return ObjectStorage()
