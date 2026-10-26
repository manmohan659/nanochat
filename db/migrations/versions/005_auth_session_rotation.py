"""One-time PKCE login codes and durable refresh token families."""
import sqlalchemy as sa
from alembic import op
revision = "005_auth_session_rotation"
down_revision = "004_add_favorited"
branch_labels = None
depends_on = None

def upgrade():
    op.create_table("auth_login_codes", sa.Column("digest", sa.String(64), primary_key=True), sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("challenge", sa.String(43), nullable=False), sa.Column("expires_at", sa.BigInteger(), nullable=False), sa.Column("consumed", sa.Boolean(), nullable=False))
    op.create_table("auth_refresh_families", sa.Column("id", sa.String(32), primary_key=True), sa.Column("revoked", sa.Boolean(), nullable=False))
    op.create_table("auth_refresh_credentials", sa.Column("digest", sa.String(64), primary_key=True), sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("family", sa.String(32), sa.ForeignKey("auth_refresh_families.id", ondelete="CASCADE"), nullable=False), sa.Column("expires_at", sa.BigInteger(), nullable=False), sa.Column("consumed", sa.Boolean(), nullable=False), sa.Column("revoked", sa.Boolean(), nullable=False))
    op.create_index("ix_auth_refresh_credentials_family", "auth_refresh_credentials", ["family"])

def downgrade():
    op.drop_table("auth_refresh_credentials")
    op.drop_table("auth_refresh_families")
    op.drop_table("auth_login_codes")
