#!/usr/bin/env bash
set -euo pipefail
# Host prerequisites for libvirt Talos (NAT internet for virbr-talos)
# See just setup-host — standalone equivalent for CI/non-just usage.
# Ensures firewalld NAT for talos-net (virbr-talos) - required for Talos image pulls (factory.talos.dev).
# libvirt_network with forward nat + bridge.zone=libvirt creates the network, but host firewalld must have masquerade.
# Run once per hypervisor host (needs sudo/polkit). Idempotent.

echo "Ensuring firewalld masquerade/forward for libvirt zone..."
if ! firewall-cmd --zone=libvirt --query-masquerade >/dev/null 2>&1; then
  echo "Enabling masquerade..."
  sudo firewall-cmd --zone=libvirt --add-masquerade --permanent || pkexec firewall-cmd --zone=libvirt --add-masquerade --permanent
  sudo firewall-cmd --zone=libvirt --add-masquerade || pkexec firewall-cmd --zone=libvirt --add-masquerade || true
fi
if ! firewall-cmd --zone=libvirt --query-forward >/dev/null 2>&1; then
  sudo firewall-cmd --zone=libvirt --add-forward --permanent || pkexec firewall-cmd --zone=libvirt --add-forward --permanent || true
  sudo firewall-cmd --zone=libvirt --add-forward || pkexec firewall-cmd --zone=libvirt --add-forward || true
fi
sudo firewall-cmd --reload 2>/dev/null || pkexec firewall-cmd --reload 2>/dev/null || true
firewall-cmd --zone=libvirt --query-masquerade && echo "✓ masquerade: yes" || echo "✗ masquerade still no"
firewall-cmd --zone=libvirt --query-forward && echo "✓ forward: yes" || echo "✗ forward still no"
