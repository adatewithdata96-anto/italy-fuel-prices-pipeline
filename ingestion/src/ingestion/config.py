"""Runtime configuration, read from environment variables.

Locally the values come from the `.env` file through Docker Compose.
On AWS they come from the ECS task definition, and credentials come from the task IAM role.
"""

import os
from dataclasses import dataclass


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "y"}


@dataclass(frozen=True)
class Settings:
    s3_bucket: str
    prices_url: str
    stations_url: str
    s3_endpoint_url: str | None = None  # None on AWS: boto3 uses the real S3 endpoint
    create_bucket: bool = False  # True only locally; on AWS the bucket is created by Terraform
    http_timeout_seconds: int = 120
    max_attempts: int = 4

    @classmethod
    def from_env(cls) -> "Settings":
        missing = [
            name
            for name in ("S3_BUCKET", "MIMIT_PRICES_URL", "MIMIT_STATIONS_URL")
            if not os.getenv(name)
        ]
        if missing:
            raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

        return cls(
            s3_bucket=os.environ["S3_BUCKET"],
            prices_url=os.environ["MIMIT_PRICES_URL"],
            stations_url=os.environ["MIMIT_STATIONS_URL"],
            s3_endpoint_url=os.getenv("S3_ENDPOINT_URL") or None,
            create_bucket=_env_bool("CREATE_BUCKET", default=False),
            http_timeout_seconds=int(os.getenv("HTTP_TIMEOUT_SECONDS", "120")),
            max_attempts=int(os.getenv("MAX_ATTEMPTS", "4")),
        )
