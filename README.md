# ejabberd (Production, TLS)

A production-ready `docker compose` setup for [ejabberd](https://www.ejabberd.im/) with TLS.

## Layout

```
.
├── docker-compose.yml
├── conf/
│   └── ejabberd.yml          # main ejabberd config (bind-mounted, read-only)
└── certs/
    ├── xmpp.example.com.pem  # fullchain + private key (PEM)
    └── dhparams.pem          # Diffie-Hellman parameters
```

## 1. Prepare certificates

ejabberd expects a single PEM containing the full certificate chain **and** the
private key. If you use Let's Encrypt:

```bash
sudo cat /etc/letsencrypt/live/xmpp.example.com/fullchain.pem \
         /etc/letsencrypt/live/xmpp.example.com/privkey.pem \
         > certs/xmpp.example.com.pem
sudo chown 9000:9000 certs/xmpp.example.com.pem
sudo chmod 640 certs/xmpp.example.com.pem
```

Generate strong DH parameters (one-time, a few minutes):

```bash
openssl dhparam -out certs/dhparams.pem 2048
```

Make sure the cert covers both `xmpp.example.com` and `conference.xmpp.example.com`
(add SANs for any vhosts/services you run).

## 2. Configure

- Edit `conf/ejabberd.yml` and replace `xmpp.example.com` with your real domain.
- Set `turn_ipv4_address` to the server's public IP.
- Adjust the `admin` ACL to your admin JID.

## 3. DNS

Create the following records for server-to-server federation:

```
_xmpp-client._tcp.example.com.  SRV 5 0 5222 xmpp.example.com.
_xmpps-client._tcp.example.com. SRV 5 0 5223 xmpp.example.com.
_xmpp-server._tcp.example.com.  SRV 5 0 5269 xmpp.example.com.
```

## 4. Start

```bash
docker compose up -d
docker compose logs -f ejabberd
```

## 5. Create the admin user

```bash
docker compose exec ejabberd ejabberdctl register admin xmpp.example.com 'STRONG_PASSWORD'
```

The web admin will be at: `https://xmpp.example.com:5443/admin`

## 6. Firewall

Open the following ports on your host/firewall:

| Port  | Proto | Purpose                          |
|-------|-------|----------------------------------|
| 5222  | TCP   | XMPP c2s (STARTTLS)              |
| 5223  | TCP   | XMPP c2s (direct TLS)            |
| 5269  | TCP   | XMPP s2s federation              |
| 5443  | TCP   | HTTPS (BOSH, WebSocket, upload)  |
| 3478  | UDP   | STUN/TURN (audio/video calls)    |

## Renewing certificates

After renewing your certificate, rebuild the bundle and reload:

```bash
docker compose exec ejabberd ejabberdctl reload_config
```

Or, for a full TLS reload:

```bash
docker compose restart ejabberd
```
# skit
