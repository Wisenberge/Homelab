# docker01 compose files (no Ansible needed)

Plain Docker Compose stacks for docker01 (10.10.0.95, Debian VM on Proxmox).

| Folder | What | Open it at |
|---|---|---|
| `tailscale/` | Connects docker01 to Tailscale | (no web UI) |
| `caddy/` | Reverse proxy for everything | see below |
| `uptime-kuma/` | Monitoring | http://10.10.0.95:3001 |
| `dns/` | Technitium DNS: ad blocking and local names | http://10.10.0.95:5380 |
| `semaphore/` | Web UI that runs the Ansible playbooks | http://10.10.0.95:3000 |

Through Caddy:

- Jellyfin (Apple TV): `http://10.10.0.95:8096`
- Uptime Kuma: `http://10.10.0.95:3001`
- Proxmox: `https://10.10.0.95:8006` (accept the certificate warning once)
- Semaphore: `http://10.10.0.95:3000`
- DNS console: `http://10.10.0.95:5380`

Tailscale, Caddy and Uptime Kuma use the same folders and container names as
the Ansible roles in `homelab-ansible`. If you switch to Ansible later, it
takes over those folders and keeps your data. After that, change settings in
Ansible, because it overwrites the compose files.

`dns/` and `semaphore/` are compose-only; Ansible doesn't manage them yet.

## 1. Install Docker (once)

SSH into docker01 and run:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo docker network create proxy
sudo mkdir -p /opt/homelab && sudo chown "$USER" /opt/homelab
```

## 2. Copy the files to the VM

From the computer that has this folder (replace `youruser`):

```bash
scp -r homelab-compose/tailscale homelab-compose/caddy homelab-compose/uptime-kuma youruser@10.10.0.95:/opt/homelab/
```

## 3. Start Tailscale

```bash
cd /opt/homelab/tailscale
cp .env.example .env && chmod 600 .env
sudo docker compose up -d
sudo docker logs tailscale        # open the login link it prints, sign in as you
```

Then, in the Tailscale admin console:

- Turn on **Disable key expiry** for docker01, or it logs out after 180 days.
- Check you can reach his Jellyfin (put in his 100.x.y.z IP). This should print `Healthy`:

  ```bash
  sudo docker exec tailscale tailscale status
  curl http://<his-tailscale-ip>:8096/health
  ```

## 4. Start Uptime Kuma

```bash
cd /opt/homelab/uptime-kuma && sudo docker compose up -d
```

## 4b. Start DNS and Semaphore

Make sure nothing else on the VM uses port 53 (this should print nothing):

```bash
sudo ss -tulpn | grep ':53 '
```

```bash
cd /opt/homelab/dns
cp .env.example .env && chmod 600 .env && nano .env      # set an admin password
sudo docker compose up -d

cd /opt/homelab/semaphore
cp .env.example .env && chmod 600 .env
head -c32 /dev/urandom | base64                          # paste as SEMAPHORE_ACCESS_KEY_ENCRYPTION
nano .env                                                # also set SEMAPHORE_ADMIN_PASSWORD
sudo docker compose up -d
```

Save the encryption key in a password manager. If you lose it, every SSH key
and secret saved in Semaphore has to be entered again.

## 5. Start Caddy

```bash
cd /opt/homelab/caddy
cp .env.example .env
nano .env                          # fill in JELLYFIN_TAILSCALE_IP and PROXMOX_IP
sudo docker compose up -d
sudo docker logs caddy --tail 30   # look for errors
```

Delete any site you don't want from `conf/Caddyfile`, then reload:

```bash
sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## 6. Apple TV

Install **Swiftfin** or **Infuse** and add the server `http://10.10.0.95:8096`.

## 7. Set up DNS

1. Open `http://10.10.0.95:5380` and log in as `admin`.
2. **Ad blocking:** go to **Settings → Blocking**, add a blocklist URL (for example the
   Hagezi "Multi Normal" list), and save.
3. **Local names:** go to **Zones → Add Zone**, create `home.arpa`, and add A records
   pointing at `10.10.0.95`, e.g. `jellyfin`, `kuma`, `semaphore`.
4. **Test it from your computer before changing the router.** This should print `10.10.0.95`:

   ```bash
   nslookup jellyfin.home.arpa 10.10.0.95
   ```

5. **UniFi:** go to **Settings → Networks → (your network) → DHCP**, set the DNS server to
   `10.10.0.95`, and save. Devices pick it up when they renew their address (or reconnect).

docker01 is now your network's DNS. If it's off, devices can't look up websites.
Don't add a public DNS like 1.1.1.1 as a second server: devices would randomly
skip your ad blocking. Later, the proper fix is a second Technitium on another
machine.

## Updating

```bash
cd /opt/homelab/<folder> && sudo docker compose pull && sudo docker compose up -d
```

## Later: moving the internet-facing part to a DMZ

Do this when you add the public domain and forward ports. Until then, nothing
is exposed, so one VM is fine.

The files are already split for it:

- **EDGE** (`tailscale/` and the EDGE sites in the Caddyfile) moves to a new small VM.
- **INTERNAL** (Uptime Kuma, Proxmox UI) stays on docker01.

1. **UniFi:** create a new Network (VLAN), e.g. "DMZ", VLAN 20, `10.10.20.0/24`.
   - In the firewall, put it in the DMZ zone. Block DMZ → your LAN; allow DMZ → internet and LAN → DMZ.
   - Forward TCP 80/443 to the new VM only.
2. **Proxmox:** tick **VLAN aware** on `vmbr0`. Create `edge01` (1 vCPU, 1 GB) with VLAN tag 20 on its network card.
3. **edge01:** install Docker, then copy `tailscale/` and `caddy/` over. Keep only the EDGE sites, including the public domain.
4. **docker01:** in the Caddyfile, keep only the INTERNAL sites. Stop its Tailscale (`docker compose down` in `tailscale/`).
5. **Tailscale:** edit the access policy so edge01 can only reach your brother's Jellyfin, not your other devices.

Jellyfin is reached over Tailscale, which only makes outgoing connections,
so edge01 never needs any access to your LAN.
