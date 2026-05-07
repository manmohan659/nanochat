# rds module

Reusable PostgreSQL RDS instance module. The app uses it for the shared
non-prod instance and the dedicated prod instance; per-runtime logical
databases and app users are bootstrapped by `scripts/bootstrap-rds-logical-db.sh`
from inside EKS.
