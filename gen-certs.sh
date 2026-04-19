#!/usr/bin/env bash
#
# gen-certs.sh — Generate TLS certificates for the ejabberd docker-compose setup.
#
# Produces, under ./certs/:
#   - <domain>.pem   : self-signed cert + private key bundle (SANs include
#                      conference.<domain>, upload.<domain>, proxy.<domain>)
#   - dhparams.pem   : Diffie-Hellman parameters
#
# The file format matches what ejabberd expects (see conf/ejabberd.yml:
# `certfiles: /opt/ejabberd/conf/certs/*.pem`).
#
# Usage:
#   ./gen-certs.sh                  # uses XMPP_DOMAIN from .env, or xmpp.example.com
#   DOMAIN=xmpp.acme.com ./gen-certs.sh
#   ./gen-certs.sh --dh-bits 4096   # stronger DH params (slower)
#   ./gen-certs.sh --days 825       # cert validity in days
#   ./gen-certs.sh --force          # overwrite existing files
#
set -euo pipefail

# ---------- defaults ----------
DH_BITS=2048
KEY_BITS=4096
DAYS=825
FORCE=0
OWNER_UID=9000
OWNER_GID=9000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/certs"

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dh-bits)   DH_BITS="$2"; shift 2 ;;
    --key-bits)  KEY_BITS="$2"; shift 2 ;;
    --days)      DAYS="$2"; shift 2 ;;
    --force)     FORCE=1; shift ;;
    --cert-dir)  CERT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ---------- determine domain ----------
if [[ -z "${DOMAIN:-}" ]]; then
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    . "${SCRIPT_DIR}/.env"
    set +a
  elif [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
    # shellcheck disable=SC1091
    set -a
    . "${SCRIPT_DIR}/.env.example"
    set +a
  fi
  DOMAIN="${XMPP_DOMAIN:-xmpp.example.com}"
fi

echo "==> Domain:       ${DOMAIN}"
echo "==> Cert dir:     ${CERT_DIR}"
echo "==> Key bits:     ${KEY_BITS}"
echo "==> DH bits:      ${DH_BITS}"
echo "==> Validity:     ${DAYS} days"

command -v openssl >/dev/null 2>&1 || {
  echo "ERROR: openssl not found in PATH" >&2
  exit 1
}

mkdir -p "${CERT_DIR}"

PEM_FILE="${CERT_DIR}/${DOMAIN}.pem"
DH_FILE="${CERT_DIR}/dhparams.pem"

# ---------- refuse to clobber unless --force ----------
if [[ -e "${PEM_FILE}" && ${FORCE} -eq 0 ]]; then
  echo "ERROR: ${PEM_FILE} already exists (use --force to overwrite)" >&2
  exit 1
fi

# ---------- work in a temp dir, move atomically at the end ----------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

KEY="${TMPDIR}/privkey.pem"
CSR="${TMPDIR}/request.csr"
CRT="${TMPDIR}/fullchain.pem"
CFG="${TMPDIR}/openssl.cnf"

# ---------- OpenSSL config with SANs ----------
cat > "${CFG}" <<EOF
[req]
default_bits       = ${KEY_BITS}
default_md         = sha256
prompt             = no
distinguished_name = dn
req_extensions     = req_ext
x509_extensions    = v3_ext

[dn]
CN = ${DOMAIN}
O  = ejabberd self-signed
OU = XMPP

[req_ext]
subjectAltName = @alt_names

[v3_ext]
basicConstraints     = critical, CA:FALSE
keyUsage             = critical, digitalSignature, keyEncipherment
extendedKeyUsage     = serverAuth, clientAuth
subjectAltName       = @alt_names
subjectKeyIdentifier = hash

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = conference.${DOMAIN}
DNS.3 = upload.${DOMAIN}
DNS.4 = proxy.${DOMAIN}
DNS.5 = pubsub.${DOMAIN}
EOF

echo "==> Generating ${KEY_BITS}-bit RSA private key..."
openssl genrsa -out "${KEY}" "${KEY_BITS}" 2>/dev/null

echo "==> Generating self-signed certificate (${DAYS} days) with SANs..."
openssl req -x509 -new -key "${KEY}" \
  -out "${CRT}" -days "${DAYS}" \
  -config "${CFG}" -extensions v3_ext 2>/dev/null

# ejabberd wants fullchain + privkey in one PEM
cat "${CRT}" "${KEY}" > "${TMPDIR}/bundle.pem"

# ---------- DH params (skip if present unless --force) ----------
if [[ -e "${DH_FILE}" && ${FORCE} -eq 0 ]]; then
  echo "==> Re-using existing ${DH_FILE}"
else
  echo "==> Generating ${DH_BITS}-bit DH parameters (this can take a while)..."
  openssl dhparam -out "${TMPDIR}/dhparams.pem" "${DH_BITS}" 2>/dev/null
  mv "${TMPDIR}/dhparams.pem" "${DH_FILE}"
fi

mv "${TMPDIR}/bundle.pem" "${PEM_FILE}"

# ---------- permissions ----------
chmod 640 "${PEM_FILE}" "${DH_FILE}"

# chown to 9000:9000 (ejabberd container user) — needs root; warn if we can't
if [[ $(id -u) -eq 0 ]]; then
  chown "${OWNER_UID}:${OWNER_GID}" "${PEM_FILE}" "${DH_FILE}"
else
  if ! chown "${OWNER_UID}:${OWNER_GID}" "${PEM_FILE}" "${DH_FILE}" 2>/dev/null; then
    echo "WARN: could not chown to ${OWNER_UID}:${OWNER_GID} (re-run with sudo if the container cannot read the files)."
  fi
fi

echo
echo "==> Done."
echo "    ${PEM_FILE}"
echo "    ${DH_FILE}"
echo
echo "Verify with:"
echo "    openssl x509 -in '${PEM_FILE}' -noout -subject -issuer -dates -ext subjectAltName"
