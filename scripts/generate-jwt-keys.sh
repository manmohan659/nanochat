#!/usr/bin/env bash
# Generate RS256 JWT key pair for samosaChaat auth service
set -e

mkdir -p .secrets
chmod 700 .secrets

openssl genrsa -out .secrets/jwt-private.pem 2048
openssl rsa -in .secrets/jwt-private.pem -pubout -out .secrets/jwt-public.pem
chmod 600 .secrets/jwt-private.pem .secrets/jwt-public.pem

echo ""
echo "Keys generated: .secrets/jwt-private.pem, .secrets/jwt-public.pem"
echo ""
echo "For EKS deploys:"
echo "export JWT_PRIVATE_KEY_FILE=.secrets/jwt-private.pem"
echo "export JWT_PUBLIC_KEY_FILE=.secrets/jwt-public.pem"
echo ""
