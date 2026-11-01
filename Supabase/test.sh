#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# PostgreSQL efímero sin puertos, sin red y sin datos del usuario. No ejecuta nada en Supabase.
export HOGAR_TEST_CONTAINER="hogar-authority-test-$$"
docker_local() {
    env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host=unix:///var/run/docker.sock "$@"
}
docker_local info >/dev/null
cleanup() { docker_local rm -f "$HOGAR_TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT HUP INT TERM
docker_local run -d --rm --name "$HOGAR_TEST_CONTAINER" --network none --tmpfs /var/lib/postgresql/data -e POSTGRES_HOST_AUTH_METHOD=trust postgres@sha256:839fbb5a4942a7758dd93e18b42ea5649807491a0545b5eeeb8f0b8bb11857a5 >/dev/null
attempt=0
until docker_local exec "$HOGAR_TEST_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 40 ]; then echo 'PostgreSQL de pruebas no está listo' >&2; exit 1; fi
    sleep 1
done
docker_local exec -i "$HOGAR_TEST_CONTAINER" psql -Xq -v ON_ERROR_STOP=1 -U postgres < Supabase/tests/bootstrap.sql
docker_local exec -i "$HOGAR_TEST_CONTAINER" psql -Xq -v ON_ERROR_STOP=1 -U postgres < Supabase/schema.sql
python3 Supabase/tests/test_authority.py
