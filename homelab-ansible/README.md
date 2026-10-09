# Homelab Ansible

Ansible playbooks for a Docker-based homelab, built to be run from [Semaphore UI](https://semaphoreui.com/). This repo describes everything, so you can rebuild the whole lab from Git.

| Playbook | Role(s) | What it does |
|---|---|---|
| `docker_host.yml` | `common`, `docker` | Base packages, timezone, automatic security updates, Docker Engine and Compose |
| `reverse_proxy.yml` | `reverse_proxy` | Caddy reverse proxy with automatic HTTPS |
| `uptime_kuma.yml` | `uptime_kuma` | Uptime Kuma monitoring behind Caddy |
| `opentofu.yml` | `opentofu` | OpenTofu container that creates Proxmox VMs |
| `tailscale.yml` | `tailscale` | Joins the proxy host to Tailscale so Caddy can reach tailnet machines |
| `ddns.yml` | `ddns` | Keeps Cloudflare DNS records pointed at your home IP |
| `maintenance.yml` | `maintenance` | OS updates, container image updates, cleanup, reboot if needed |
| `config_backup.yml` | `config_backup` | Commits each host's config files to a Git repo |
| `site.yml` | all of the above except maintenance/backup | Full rebuild |

Supported hosts: Debian 12/13 and Ubuntu 22.04/24.04. Requires ansible-core 2.15 or newer.

## How it fits together

```
/opt/homelab/                 one folder per app, each with a compose.yml
├── caddy/                    reverse proxy (ports 80/443)
├── uptime-kuma/
└── opentofu/                 tofu.sh + workspace/ (VM config and state)

Docker network "proxy"        Caddy reaches apps by container name, e.g. uptime-kuma:3001
```

Every role's variables live in `roles/<role>/defaults/main.yml`, with a comment on each one. Those files are the reference for everything you can change.

## Where your settings go

Three places, from lowest to highest priority:

1. **Role defaults** (`roles/*/defaults/main.yml`): sensible starting values. Don't edit these.
2. **Inventory** (`inventory/hosts.yml`, `inventory/group_vars/all.yml`): your hosts, IPs and non-secret settings. Commit them.
3. **Semaphore**: per-environment values and **all secrets**. Secrets never go in Git.

## One-time preparation

### 1. Proxmox API token for OpenTofu

Run on the Proxmox host (Proxmox VE 9):

```bash
pveum role add TofuProvisioner -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.GuestAgent.Audit VM.Migrate VM.PowerMgmt"
pveum user add tofu@pve
pveum aclmod / -user tofu@pve -role TofuProvisioner
pveum user token add tofu@pve homelab --privsep 0
```

Save the token it prints as `tofu@pve!homelab=<uuid>`. On Proxmox VE 8, replace `VM.GuestAgent.Audit` with `VM.Monitor`.

Then enable image imports on the image storage: **Datacenter → Storage → local → Edit → Content → add "Import"**.

### 2. Git repo for config backups

Create a **private** repo (e.g. `homelab-configs`) with at least one commit, such as a README. Generate a key pair with `ssh-keygen -t ed25519 -f homelab-backup`, then add the public key as a deploy key **with write access**.

### 3. Hosts

Each host needs SSH access for the `ansible_user` in `inventory/group_vars/all.yml`, with passwordless sudo.

## Semaphore setup

1. **Key Store**
   - An SSH key that logs in to your hosts.
   - Credentials Semaphore can use to clone this repo.
2. **Repository**: this repo's URL and branch.
3. **Inventory**: type *File*, path `inventory/hosts.yml`, using the SSH key above.
4. **Variable Group / Environment** (e.g. `homelab`):
   - **Extra variables** (non-secret; example below).
   - **Secrets** (type *Variable*):

     | Secret | Used by |
     |---|---|
     | `opentofu_proxmox_api_token` | opentofu |
     | `config_backup_ssh_private_key` | config_backup (paste the whole private key) |
     | `reverse_proxy_cloudflare_api_token` | reverse_proxy (only in `cloudflare` mode) and ddns |
     | `tailscale_auth_key` | tailscale (only needed for the first run) |
     | `ddns_cloudflare_api_token` | ddns (only if it needs a different token from the reverse proxy) |

5. **Task Templates**: one per playbook:

   | Template | Playbook | Suggested schedule |
   |---|---|---|
   | Setup Docker hosts | `docker_host.yml` | manual |
   | Reverse proxy | `reverse_proxy.yml` | manual |
   | Uptime Kuma | `uptime_kuma.yml` | manual |
   | Proxmox VMs | `opentofu.yml` | manual |
   | Tailscale | `tailscale.yml` | manual |
   | Dynamic DNS | `ddns.yml` | manual |
   | Maintenance | `maintenance.yml` | weekly, e.g. `0 4 * * 0` |
   | Config backup | `config_backup.yml` | daily, e.g. `0 3 * * *` |
   | Full rebuild | `site.yml` | manual |

   On the **Proxmox VMs** template, add a Survey variable `opentofu_action` (values `plan` / `apply`). That way you choose on every run whether to only preview or actually make changes.

Semaphore installs the collections in `collections/requirements.yml` automatically. Use the template's **Limit** field to run against a single host.

Example **Extra variables** for the environment:

```json
{
  "reverse_proxy_tls_mode": "cloudflare",
  "reverse_proxy_acme_email": "you@example.com",
  "reverse_proxy_sites": [
    { "domain": "kuma.home.example.com", "upstream": "uptime-kuma:3001" },
    { "domain": "pve.home.example.com", "upstream": "https://192.168.1.10:8006", "skip_tls_verify": true }
  ],

  "opentofu_proxmox_endpoint": "https://192.168.1.10:8006/",
  "opentofu_proxmox_node": "pve",
  "opentofu_vm_ssh_public_keys": ["ssh-ed25519 AAAA... you@laptop"],
  "opentofu_vms": [
    { "name": "docker02", "cores": 2, "memory_mb": 4096, "disk_gb": 32, "ip": "192.168.1.21/24", "tags": ["docker"] }
  ],

  "config_backup_repo_url": "git@github.com:you/homelab-configs.git"
}
```

## Everyday tasks

- **Add a website to the proxy:** add an entry to `reverse_proxy_sites` and run *Reverse proxy*. Caddy reloads without downtime.
- **Create a VM:** add an entry to `opentofu_vms`, run *Proxmox VMs* with `plan`, check the output, then run it again with `apply`. Afterwards, add the VM to `inventory/hosts.yml` and run *Setup Docker hosts*.
- **Delete a VM:** remove it from `opentofu_vms` and run `plan`, then `apply`. **The plan shows the VM being destroyed. Read it before applying.**
- **Add a new app:** copy `roles/uptime_kuma` as a template. It's a compose file, a data folder, and one `docker_compose_v2` task. Join it to the `proxy` network and add a `reverse_proxy_sites` entry.

## Watching a shared Tailscale server at home (e.g. Jellyfin on an Apple TV)

Only your server runs Tailscale. Caddy listens on a port on your home network and forwards to the shared machine over Tailscale. Devices like an Apple TV just connect to your server. You don't need a domain, port forwarding or certificates.

```
Apple TV → http://192.168.1.20:8096 → Caddy on docker01 → Tailscale → his server 100.x.y.z:8096
```

1. Create a Tailscale auth key **without tags** (Settings → Keys) and save it in Semaphore as the secret `tailscale_auth_key`.
2. Add these extra variables, using his server's Tailscale IP. `"reverse_proxy_sites": []` removes the example domain sites. Leave it out if you already have real ones.

   ```json
   {
     "tailscale_check_urls": ["http://100.101.102.103:8096/health"],
     "reverse_proxy_sites": [],
     "reverse_proxy_lan_sites": [
       { "port": 8096, "upstream": "100.101.102.103:8096" }
     ]
   }
   ```

3. Run *Tailscale*, then *Reverse proxy*.
4. In the Tailscale admin console, choose **Disable key expiry** on docker01.
5. On the Apple TV, install Swiftfin or Infuse and add the server `http://<docker01's LAN IP>:8096`.

Don't forward these ports on your router. If you add a domain later (next section), you can keep the LAN site too.

## Putting someone else's server on a domain (e.g. your brother's Jellyfin)

```
Viewer's browser
  → jellyfin.hisdomain.com        DNS points at your home IP (kept current by ddns)
  → your router, ports 80/443     forwarded to docker01
  → Caddy on docker01             HTTPS certificate from Let's Encrypt
  → Tailscale                     encrypted tunnel to his server
  → his server 100.x.y.z:8096     Jellyfin
```

Tailscale addresses (`100.x.y.z`) only work inside Tailscale, so a public DNS record can't point at them directly. Your Caddy host acts as the public front door and forwards traffic over Tailscale.

**Your brother's side (about 5 minutes):**

1. Install Tailscale on his server and sign in with his own account.
2. Share the server with you: in the Tailscale admin console, go to **Machines → ⋯ next to the server → Share**, and send the invite to your Tailscale account. Accept it on your side.
   - Shared machines can only answer connections. His server can't reach anything on your network.
3. Send you the server's Tailscale IP (`100.x.y.z`).

**Your side:**

1. **Domain:** buy it anywhere and add it to Cloudflare (free plan), or buy it through Cloudflare Registrar.
2. **Cloudflare token:**
   - Go to **My Profile → API Tokens → Create Token**, choose the *Edit zone DNS* template, and select the domain.
   - If the reverse proxy already uses a Cloudflare token, you can add this domain to that token instead.
3. **Router:** forward TCP ports 80 and 443 to docker01.
   - If your router's WAN IP differs from what https://ifconfig.me shows, your ISP uses CGNAT and port forwarding won't work. In that case, run this setup on a small VPS instead.
4. **Tailscale auth key:**
   - Go to **Settings → Keys → Generate auth key**. Don't add tags: a shared machine is only visible to devices you own.
   - After the first run, find the new machine under **Machines** and choose **Disable key expiry**. Otherwise it logs out after 180 days.
5. **Semaphore:**
   - Add the secrets `tailscale_auth_key` and `ddns_cloudflare_api_token`.
   - Add these extra variables. Keep your existing sites in `reverse_proxy_sites`, because this variable replaces the whole list.

   ```json
   {
     "tailscale_check_urls": ["http://100.101.102.103:8096/health"],
     "ddns_domains": ["jellyfin.hisdomain.com"],
     "reverse_proxy_acme_email": "you@example.com",
     "reverse_proxy_sites": [
       { "domain": "jellyfin.hisdomain.com", "upstream": "100.101.102.103:8096", "tls_mode": "acme" }
     ]
   }
   ```

6. **Run** *Tailscale*, then *Dynamic DNS*, then *Reverse proxy*.
   - The Tailscale run fails with an explanation if it can't reach his Jellyfin.
7. **Jellyfin setting:** the Tailscale run prints docker01's Tailscale IP. Your brother adds it under **Jellyfin → Dashboard → Networking → Known proxies**, then restarts Jellyfin. This lets Jellyfin see viewers' real IPs instead of your proxy's.
8. **Test** from a phone on mobile data (not your Wi-Fi): `https://jellyfin.hisdomain.com`.

Good to know:

- **Every stream passes through your internet connection**, so your upload speed limits video quality. The Tailscale run lists peers: *direct* is the fast path, while *relay* works but is slower.
- **The Cloudflare record must be "DNS only" (grey cloud).** Cloudflare's proxy isn't allowed for video streaming on non-Enterprise plans. The updater creates new records as DNS only, but it keeps the existing setting on records that already exist, so check it.
- **Only expose apps that have their own login**, like Jellyfin, and give every Jellyfin user a strong password. Reach everything else on his server over Tailscale.

## Rebuilding from scratch

1. Reinstall the OS on the host(s) and make sure you can SSH in.
2. Run **Full rebuild** (`site.yml`). This recreates Docker, every container stack, and the OpenTofu setup from this repo.
3. Restore app data (the `data/` folders) from your normal backups. These are deliberately kept out of Git.
4. If the Docker host itself was lost, copy `terraform.tfstate` from the config-backup repo (`<host>/opt/homelab/opentofu/workspace/`) back into place before running `apply`. Otherwise OpenTofu won't know your existing VMs.

**What config_backup commits:** `/opt/homelab` plus key files under `/etc`, one folder per host.

**What it never commits:** `.env` files, keys, `data/` and `state/` folders (including Tailscale's login), and provider downloads. The OpenTofu state file *is* included, which is why the backup repo must be private.

## Running locally (optional)

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook docker_host.yml --limit docker01
ansible-playbook opentofu.yml -e opentofu_action=plan -e opentofu_proxmox_api_token='tofu@pve!homelab=...'
```
