# 4. Single Control-Plane for 32 GiB Homelab (1×6 + 3×4)

* **Status:** Accepted
* **Date:** 2026-09-06
* **Deciders:** Seom88
* **Tags:** talos, proxmox, etcd, topology, homelab, cost

## Context

### Where this ADR lives

This decision is about **substrate topology** — Proxmox VM sizing, Talos
`controlplane` vs `worker` roles, etcd quorum, and Longhorn `UserVolumeConfig`
placement. It belongs in `infra-talos-homelab/docs/adr/` (this repo), not in
the companion GitOps repo `secured-gitops-tailscale-homelab/docs/adrs/`.
That repo owns platform decisions (ArgoCD, Vault, SeaweedFS, monitoring);
this repo owns how the VMs that host the platform are provisioned. See
[Decisions](./../decisions.md) and [Architecture](./../architecture.md).

### The 32 GiB hard ceiling

`pve01` is a single-node Proxmox VE host:

* **Host:** Intel i7-8700T (6c/12t), **32 GiB physical, 30.97 GiB usable**
  (`pve01 status` / `free -h`). No second PVE node.
* **Current allocation (pre-decision):** `3 × 6 GiB` control-plane VMs
  (`5836 MiB` visible each after overhead) + `1 × 4 GiB` TrueNAS VM
  (`truenas-core`) = **22 GiB assigned** to guests.
* **Host pressure:** `77.5%` host memory used; Proxmox reports high
  `loadavg ≈ 21` (6c host, `pvestatd` + `kvm` + `zfs`/`arc` contention).
  Only **`~1.4 GiB AVAILABLE` per Talos node** (`talosctl memory` / Kubernetes
  `Allocatable` after kube-reserved + system-reserved).
* **Talos process footprint** (`talosctl -n 10.10.0.11 ps` — representative):

  ```
  kube-apiserver   1.3–1.8 GiB  (peaks 1.8 GiB under list/watch pressure)
  etcd             0.4–0.7 GiB
  kube-controller-manager  0.2 GiB
  kube-scheduler   0.1 GiB
  cilium-agent     0.2–0.4 GiB
  longhorn-manager 0.2 GiB  (when data disk present)
  ```

  On every CP the **kube-apiserver alone consumes >50% of AVAILABLE**.
  Two of three etcd members flip to `Fail` under load:

  ```
  etcd: Fail  — slow fdatasync 1.5–2.0s (threshold 500ms)
        Write cache disabled on vda (cache=none / writeback off) + OOM kills → WAL fsync stalls → leader election flaps
  ```

  Root cause is the combination of memory pressure (page reclaim stalls the
  WAL `fdatasync`) and `virtio0` without write-back cache on the system disk.

### The wishlist that does not fit

Planned GitOps workloads (ArgoCD waves `01`–`04`):

__Note:__ estimation.

| Workload | Est. request | Note |
|----------|-------------|------|
| Technitium DNS | 0.3 GiB | replaces CoreDNS forwarding |
| Homepage / Homarr | 0.2 GiB | dashboard |
| CNPG (CloudNativePG) operator + 1 Postgres cluster | 1.0 GiB | Postgres 512 MiB + operator |
| Nextcloud (php-fpm + redis) | 1.5 GiB | file sync |
| Immich (server + ml + redis + postgres) | 1.5 GiB | photo — largest consumer |
| **Total wishlist** | **~4–5 GiB requests** | before Longhorn replication overhead |

With `3 × 6` CPs, allocatable is `3 × 1.4 ≈ 4.2 GiB` **total** — already
saturated by Cilium + Longhorn + kube-system. The wishlist alone needs another
`4–5 GiB` of `requests`. Eviction and OOM follow.

### Why the obvious fixes do not work on 32 GiB

* **Upsize to `3 × 8 GiB` CPs:** `3 × 8 + 4 (TrueNAS) = 28 GiB` assigned →
  **`≈95% host memory`** after Proxmox; host OOM or ballooning kills a
  `kvm` process under load. Rejected — exceeds the `80%` safety rule for a
  single-node PVE that also runs ZFS.
* **Rightsize `3 × 6` (Option A — keep HA, tune requests):** Trim `kube-apiserver`
  `--max-requests-inflight`, set `Guaranteed` QoS, lower Longhorn replica count
  to 2, etc. Recovers `~0.5–0.8 GiB` per node but still leaves `~1.9 GiB`
  AVAILABLE per CP vs `4–5 GiB` wishlist. Delays the problem one workload;
  does not create a scalable worker pool. Kept as a **deferred tuning** (see
  Alternatives), not a topology fix.
* **Externalize TrueNAS:** Moving the 4 GiB TrueNAS to bare metal or a second
  host would free `4 GiB` — but the hardware does not exist today. Deferred.
* **64 GiB RAM upgrade:** Correct long-term fix; blocked on budget until
  employment resumes.

### Purpose of this homelab

This is a **learning homelab, not an enterprise prod cluster**. The primary
goal is to run a realistic GitOps platform (Cilium, Longhorn, Vault,
SeaweedFS/RustFS, CNPG, Velero) and ship workloads. **HA of etcd is a
secondary concern** when the alternative is not being able to schedule the
workloads that justify having the cluster at all. Sacrificing etcd quorum
for schedulable capacity is an explicit, reversible tradeoff for this stage.

## Decision

Run a **single control-plane** and scale horizontally with **three workers**
on the same `pve01` host: **`1 × 6 + 3 × 4`** (GiB).

### Node specs

| Role | Count | Hostname | IP | Cores | Memory | Datastore | Disk 0 (EPHEMERAL) | Disk 1 (data) | `allow_scheduling` |
|------|-------|----------|----|-------|--------|-----------|---------------------|---------------|--------------------|
| control-plane | 1 | `talos-cp1` | `10.10.0.11` | 4 | `6 × 1024` | `ssd01` | `40 GiB virtio0` | **none** | `false` |
| worker | 3 | `talos-w1` | `10.10.0.101` | 4 | `4 × 1024` | `ssd01` | `40 GiB virtio0` | `100 GiB virtio1` | `true` |

* **Control-plane:** Dedicated `controlplane` Talos role. Tainted
  `node-role.kubernetes.io/control-plane:NoSchedule` (Talos default when
  `allow_scheduling = false`), not schedulable. No `UserVolumeConfig` — only
  the `40 GiB` `EPHEMERAL` partition (`/var` on `virtio0`). No Longhorn
  replicas may land on it (`Scheduling Disabled` in Longhorn node view, but
  the `longhorn-manager` DaemonSet still runs for CSI control-plane hooks).
* **Workers:** `worker` Talos role, `allow_scheduling = true`. Each carries a
  `100 GiB virtio1` data disk backing `UserVolumeConfig "data"` →
  `/var/mnt/data` (`modules/proxmox/main.tf: data_volume_patch`). Longhorn
  replicas are constrained to workers; Cilium `DaemonSet` runs on all 4 nodes.

### Terraform (`environments/proxmox/prod/terraform.tfvars`)

```hcl
nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.0.11"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = false
    # no data_disk_size — EPHEMERAL only, no Longhorn replica target
  }
]

nodes_worker = [
  {
    hostname       = "talos-w1"
    ip             = "10.10.0.101"
    cores          = 4
    memory         = 4 * 1024
    proxmox_node   = "pve01"
    disk_size      = 40
    datastore      = "ssd01"
    data_disk_size = 100
  },
  {
    hostname       = "talos-w2"
    ip             = "10.10.0.102"
    cores          = 4
    memory         = 4 * 1024
    proxmox_node   = "pve01"
    disk_size      = 40
    datastore      = "ssd01"
    data_disk_size = 100
  },
  {
    hostname       = "talos-w3"
    ip             = "10.10.0.103"
    cores          = 4
    memory         = 4 * 1024
    proxmox_node   = "pve01"
    disk_size      = 40
    datastore      = "ssd01"
    data_disk_size = 100
  },
]
```

`modules/talos-cluster/main.tf` maps `allow_scheduling` to the Talos
`machineConfig.machine.features.kubernetesAllowSchedulingOnControlPlanes`
patch and the control-plane `NoSchedule` taint. No change to
`modules/proxmox/main.tf` VM resource shape — `data_disk_size = null`
omits the dynamic `virtio1` block.

### Substrate behavior after the change

* `data.talos_cluster_health` now targets `control_plane_nodes = ["10.10.0.11"]`
  only. Single-CP health gate still blocks `apply` until `kube-apiserver` is
  `Running`.
* Cilium and Longhorn: `DaemonSet`/`manager` on all 4 nodes, but **Longhorn
  replica scheduling disabled on `talos-cp1`** (UI: `Node → Scheduling →
  Disable`; the Terraform path is the absence of a data disk — Longhorn
  marks the node `Schedulable = false` when no default disk has free space).
  All `RecurringJobs` and replica counts assume 3 storage nodes.
* KubePrism (`localhost:7445`) still fronts the single apiserver; no VIP L2
  failover is needed with one CP.

### Revert path (intentionally trivial)

This is a **`terraform.tfvars`-only change**. Re-adding two control-planes
is `terraform apply` with no state surgery on the workers:

```hcl
# revert to 3×6 HA when RAM/employment allows
nodes_cp = [
  { hostname = "talos-cp1", ip = "10.10.0.11", memory = 6*1024, ... , allow_scheduling = true, data_disk_size = 100 },
  { hostname = "talos-cp2", ip = "10.10.0.12", memory = 6*1024, ... , allow_scheduling = true, data_disk_size = 100 },
  { hostname = "talos-cp3", ip = "10.10.0.13", memory = 6*1024, ... , allow_scheduling = true, data_disk_size = 100 },
]
# workers stay 3×4 or grow to 3×6 — independent of CP count
```

Talos re-joins etcd on the new members via `talosctl etcd join` (see
Restore Guide). No Cilium/Longhorn reinstall required.

## Consequences

### Positive

* **−2 GiB assigned:** `20 GiB` total (`6 + 3×4 + 4 TrueNAS`) vs `22 GiB` before
  → host drops from **`77.5% → ~70%` used**. Headroom for ZFS `arc` and host
  bursts; `loadavg` contention reduced.
* **~3 GiB AVAILABLE on the single CP:** With one `kube-apiserver` (1.3–1.8 GiB)
  and one `etcd` (0.4–0.7 GiB) sharing no noisy neighbors, `talosctl memory`
  shows `~3.0 GiB AVAILABLE` on `talos-cp1` vs `1.4 GiB` per node before.
  Fewer WAL stalls; `etcd Fail` clears without tuning `fdatasync`.
* **Workers are horizontally scalable:** Each worker contributes `~2.5–3.0 GiB`
  allocatable. `3 × 4` workers give `~7.5–9 GiB` for workloads — enough for
  the `4–5 GiB` wishlist **plus** buffer for Longhorn replica overhead
  (`2×` replication: `~1.5×` usable, writes on workers only).
* **Placement correctness:** Longhorn replicas land only on workers with
  `virtio1` data disks; CP is not a storage failure domain. Cilium `DaemonSet`
  coverage unchanged.
* **Unblocks GitOps roadmap:** Technitium → Homepage → CNPG → Nextcloud →
  Immich fits without overcommitting `requests`. Vertical scaling of workers
  to `6–8 GiB` is `terraform.tfvars` + `apply` (rolling `talos_machine`
  update per worker, no etcd risk).
* **Cost zero:** No hardware spend; defers the `64 GiB` upgrade to when budget
  exists.

### Negative / Risks

* **Single point of failure — etcd and apiserver:** Loss of `talos-cp1` makes
  the cluster **unavailable**. No quorum, no leader election, no API writes.
  `RTO 15–30 min` to restore from backup or rebuild the VM (measured: `terraform
  apply -replace=proxmox_virtual_environment_vm.talos["talos-cp1"]` + Talos
  bootstrap + `talosctl bootstrap` ≈ 20 min if snapshots are healthy).

* **No rolling upgrade of the control-plane without downtime:** Talos/K8s
  upgrades on `talos-cp1` are `drain = false` + reboot. API is down for
  `~2–4 min` during `talos_machine` image swap. Workloads on workers keep
  running (kubelet uses cached manifests), but no new scheduling/admission
  until the apiserver returns. Must be announced as a maintenance window.

* **Backups are mandatory, not optional:**

  | Layer | Tool | Schedule | Target | Restore test |
  |-------|------|----------|--------|--------------|
  | etcd snapshot | `talosctl etcd snapshot` (cron via `systemd` on `talos-cp1` or `CronJob` with host mount) | hourly | RustFS (`SeaweedFS` S3 via `s3` backend `terraform-homelab`) | monthly `talosctl etcd restore` on a throwaway VM |
  | Persistent volumes | Velero + Restic | hourly | RustFS S3 | monthly `velero restore` |
  | Terraform state | `s3` backend (`terraform-homelab` bucket) | on `apply` | RustFS | `terraform init -reconfigure` |

  Without hourly snapshots, a CP disk loss means rebuilding etcd from scratch
  and re-pushing GitOps (ArgoCD recovers, but PVC data without Velero is
  gone).

* **Monitoring gap must be closed:** Add `KubeControlPlaneDown` /
  `EtcdMembersDown` alert (`kube-prometheus-stack` in GitOps) firing when
  `up{job="apiserver"} == 0` or `etcd_server_has_leader == 0` for `>2m`.
  Alert goes to the same channel as Velero failures — otherwise SPOF is
  silent.

* **Longhorn degraded during worker loss:** With 3 workers and `replicas: 2`,
  one worker down leaves one remaining replica per volume — no redundancy
  until the worker returns. `replicas: 3` would be safer but costs `3×`
  storage; deferred until workers are `6–8 GiB`.

**Mitigations adopted along with this ADR:**

* `talos-cp1` gets `cache = writeback` avoided — keep `cache=none` but raise
  `memory` to `6 GiB` and pin `etcd` to no neighbor contention. `etcd`
  `--quota-backend-bytes 2GiB` and defrag on schedule.
* Documented backup runbook in `docs/operations.md` (Velero + `talosctl etcd
  snapshot` to RustFS) and verified restore before marking this ADR `Accepted`.
* `PDBs` for critical singletons (`cilium-operator`, `longhorn-manager`,
  `argocd`) set to `maxUnavailable: 0` so worker drains do not evict them
  simultaneously.

## Alternatives Considered

| # | Alternative | Shape | Why not chosen |
|---|-------------|-------|----------------|
| **A** | **3×6 rightsized (keep HA)** | Keep `3 × 6` CPs, rightsize `requests`/`limits`, lower `kube-apiserver --max-requests-inflight`, Longhorn `replicas: 2`, Cilium `operator replicas: 1`. | Recovers only `~0.5–0.8 GiB` per node (`AVAILABLE ~1.9 GiB`). Still no room for the `4–5 GiB` wishlist; next workload re-triggers OOM. Keeps quorum but sacrifices the learning goal. **Deferred as tuning on top of the chosen topology** — apply the tunings to `1×6` as well. |
| **B** | **3×6 + 1×4 worker** | Keep `3 × 6` CPs, add one `4 GiB` worker (`22 + 4 = 26 GiB` → `≈88%` host). | Adds only `~2.5 GiB` allocatable (one worker). Host at `88%` is past the `80%` single-node safety margin; `loadavg` worsens with 5 `kvm` procs on 6c. Still needs `≥2` workers for Longhorn `2×` replicas — effectively option C with less flexibility. |
| **C** | **Externalize TrueNAS** | Move `truenas-core` (4 GiB) off `pve01` to bare metal / second host. Frees `4 GiB` without touching K8s. | Correct but requires hardware that does not exist. No budget path today. **Follow-up when a second host is available** — then `3×6 + 3×4` fits in `32 GiB` with `~62%` host. |
| **D** | **64 GiB RAM upgrade** | Replace/extend DIMMs to `64 GiB` usable; keep `3×8 + 3×4` or similar. | Ideal long-term fix. Blocked on employment/budget. **Explicit revert trigger** for this ADR (see below). |
| **E** | **K3s / single-node K8s** | Replace Talos with K3s single-node (`--disable etcd` or embedded SQLite). | Loses Talos immutability, Image Factory versioning, and the `talos-cluster` Terraform contract that this repo teaches. Rejected — learning goal is Talos/K8s, not minimizing control-plane cost at all costs. |

Chosen alternative is **this ADR (1×6 + 3×4)** because it is the only shape
that fits the `30.97 GiB` ceiling, keeps the learning stack (Talos, Cilium,
Longhorn, ArgoCD), and is reversible in one `tfvars` edit.

## Restore Guide — Scale back to 3 control-planes

> Run when `pve01` has `≥64 GiB` usable or a second PVE node exists, or when
> employment resumes and budget allows the RAM upgrade. This guide restores
> etcd HA without re-creating the workers.

### 1. Provision the RAM / host

* Physically install `64 GiB` (or add `pve02` to the SDN zone — then also
  follow ADR 003 Restore Guide for multi-node `sdn_ensure_applied`).
* Verify `free -h` / `pve01 status` shows `≥60 GiB` usable before proceeding.

### 2. Expand `terraform.tfvars`

```hcl
nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.0.11"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = false   # keep false — workers still carry workloads
    data_disk_size   = 100      # re-add Longhorn data disk for HA replicas
  },
  {
    hostname         = "talos-cp2"
    ip               = "10.10.0.12"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = false
    data_disk_size   = 100
  },
  {
    hostname         = "talos-cp3"
    ip               = "10.10.0.13"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = false
    data_disk_size   = 100
  },
]

# optionally grow workers at the same time
nodes_worker = [
  { hostname = "talos-w1", ip = "10.10.0.101", cores = 4, memory = 6 * 1024, proxmox_node = "pve01", disk_size = 40, datastore = "ssd01", data_disk_size = 100 },
  { hostname = "talos-w2", ip = "10.10.0.102", cores = 4, memory = 6 * 1024, proxmox_node = "pve01", disk_size = 40, datastore = "ssd01", data_disk_size = 100 },
  { hostname = "talos-w3", ip = "10.10.0.103", cores = 4, memory = 6 * 1024, proxmox_node = "pve01", disk_size = 40, datastore = "ssd01", data_disk_size = 100 },
]
```

### 3. Apply — create the two new CP VMs

```bash
just provider=proxmox env=prod tf-apply
# or: terraform -chdir=environments/proxmox/prod apply
# New VMs talos-cp2 / talos-cp3 boot Talos; module.talos generates
# talos_machine for each and talos_cluster with cp_ips = [11,12,13].
```

### 4. Join etcd members

Talos does not auto-join etcd on `apply` when scaling from 1 → 3. Join
explicitly after the VMs are `Ready`:

```bash
# from a machine with talosconfig
talosctl -n 10.10.0.11 etcd members        # should show only cp1 as leader
talosctl -n 10.10.0.12 etcd join --nodes 10.10.0.11
talosctl -n 10.10.0.13 etcd join --nodes 10.10.0.11
talosctl -n 10.10.0.11 etcd members        # expect 3 members, 1 leader
kubectl get nodes                         # 6 nodes Ready (3 CP + 3 workers)
```

If `talosctl etcd join` is unavailable on your Talos version, the
equivalent is `talosctl -n <new-cp> bootstrap` with the existing
`talos_machine_secrets` — `modules/talos-cluster` already wires
`machine_secrets` and `client_configuration` for the new nodes.

### 5. Re-enable scheduling / Longhorn on CPs (if desired)

With `64 GiB`, CP data disks are worthwhile — Longhorn can keep `replicas: 3`
across `6` nodes (3 CP + 3 workers). Remove the `Scheduling Disabled` taint
in Longhorn UI or via `kubectl annotate node talos-cp WasSchedulable=true`
if you previously disabled it. Otherwise keep `allow_scheduling = false` and
let Longhorn use only workers.

### 6. Verify HA

```bash
talosctl -n 10.10.0.11,10.10.0.12,10.10.0.13 etcd status
kubectl -n kube-system get pods -o wide | grep etcd
# kill one CP VM (qm stop 101) and confirm apiserver stays up via another CP IP
kubectl --server https://10.10.0.12:6443 get nodes
```

### 7. Update this ADR

Mark this ADR `Superseded by <new ADR>` and create the successor ADR
(e.g. `005-ha-control-plane-restored.md`) referencing this Restore Guide.

## Follow-up

* [ ] When employment resumes, execute the **64 GiB upgrade** (Alternative D)
  and run the **Restore Guide** above — reintroduce `talos-cp2`/`talos-cp3`
  (`6 GiB` each, `allow_scheduling = false`, `data_disk_size = 100`) and
  re-join etcd. Workers stay `3×4` initially, then grow to `3×6` or `3×8`
  after verifying host at `<80%`.
* [ ] Apply **Option A tunings** on top of `1×6`: `kube-apiserver`
  `--max-requests-inflight` / `--max-mutating-requests-inflight`,
  `etcd --quota-backend-bytes`, Cilium `operator` `replicas: 1`, Longhorn
  `replicaCount: 2` — recover `~0.5 GiB` even on the single CP.
* [ ] Harden the **backup runbook** (`docs/operations.md`): Velero hourly to
  RustFS S3 (`SeaweedFS` bucket `velero`), `talosctl etcd snapshot` hourly to
  RustFS, monthly restore drill. Gate this ADR on a green drill.
* [ ] Add **control-plane alerts** (`KubeControlPlaneDown`,
  `EtcdNoLeader`, `VeleroBackupFailed`) to `kube-prometheus-stack` in GitOps.
* [ ] Re-evaluate **Alternative C** (externalize TrueNAS) if a second host
  appears — even without `64 GiB`, offloading `4 GiB` lets `3×6 + 3×2` fit
  at `~75%` host.

## References

* `environments/proxmox/prod/terraform.tfvars` — `nodes_cp` / `nodes_worker` (this ADR's `1×6 + 3×4` shape).
* `modules/proxmox/main.tf` — `proxmox_virtual_environment_vm.talos` / `talos_worker`, `dynamic "disk"` for `virtio1`, `data_volume_patch` / `UserVolumeConfig "data"` (`/var/mnt/data`).
* `modules/talos-cluster/main.tf` — `talos_machine` `allow_scheduling` / taint, `talos_cluster` `control_plane_nodes`, `extraMounts` + `UserVolumeConfig`.
* `docs/decisions.md` — stack choices; this ADR is the topology companion to
  [Talos vs kubeadm](./../decisions.md#1-talos-linux-vs-kubeadm) and
  [Longhorn vs Ceph](./../decisions.md#5-longhorn-vs-ceph-rook).
* `docs/architecture.md` — provider topologies, SDN `talosvn` `10.10.0.0/24`.
* `docs/adr/003-sdn-snat-runtime-drift.md` — single-node SDN limitation that also lifts when scaling to multi-node.
* `talosctl -n 10.10.0.11 ps` / `talosctl memory` / `pve01 status` — measurements cited in Context (apiserver `1.3–1.8 GiB`, `AVAILABLE 1.4 GiB`, `loadavg 21`, `fdatasync 1.5–2s`).
* Companion repo: `secured-gitops-tailscale-homelab/docs/adrs/` — platform ADRs (ArgoCD, Vault, SeaweedFS, Velero); infra decisions stay here.

## TODO

* [ ] Apply `1×6 + 3×4` via `terraform.tfvars` and verify `terraform validate` + `terraform plan` shows `1 to add, 2 to destroy` for CPs and `3 to add` for workers.
* [ ] Post-apply: `talosctl -n 10.10.0.11 etcd members` shows single leader; `kubectl get nodes` shows 4 Ready; Longhorn UI shows `Scheduling Disabled` on `talos-cp1` and `Schedulable` on `w1–w3`.
* [ ] Verify `iptables -t nat -L POSTROUTING` still has `MASQUERADE 10.10.0.0/24` and `talos_cluster_health` passes on the single CP.
* [ ] Run a Velero backup + `talosctl etcd snapshot` to RustFS S3 and a test restore before scheduling wishlist workloads.
* [ ] Gate wishlist (CNPG, Nextcloud, Immich) on `KubeControlPlaneDown` alert being green.
* [ ] When `64 GiB` lands, run Restore Guide and supersede this ADR.

---

*ADR 004 follows MADR 2.3.0 structure, matching ADR 001/002/003 formatting.*
*Provenance: pve01 30.97 GiB usable, 3×5836 MiB + 4 GiB TrueNAS = 22 GiB assigned, 77.5% host, AVAILABLE 1.4 GiB, loadavg 21, etcd Fail fdatasync 1.5–2s, apiserver 1.3–1.8 GiB, wishlist +4–5 GiB, 3×8 → 95% host — single-CP tradeoff for learning homelab, reversible via tfvars.*
*Status Accepted on 2026-09-06 — single control-plane until RAM upgrade / employment.*
*Review trigger: employment / 64 GiB upgrade or second PVE node — run Restore Guide.*
*Contact: Seom88.*
