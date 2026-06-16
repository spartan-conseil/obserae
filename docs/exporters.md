# Configuring Exporters

obserae only sees the flows your network devices send it. This page shows how
to turn on flow export on the gear you already have — routers, switches,
firewalls, hypervisors and host probes — and point it at obserae.

obserae ingests **NetFlow v5, NetFlow v9 and IPFIX** over UDP:

| Protocol            | Default UDP port |
|---------------------|------------------|
| NetFlow v5 / v9     | `2055`           |
| IPFIX (a.k.a. v10)  | `4739`           |

Point each device at `<obserae-host>` on the port that matches the protocol it
sends. When you have the choice, prefer **NetFlow v9 or IPFIX** over v5 — v5 is
IPv4-only and carries fewer fields.

> **obserae needs NetFlow or IPFIX — not sFlow, and not cloud flow logs.**
> A number of switches export only **sFlow** (a different, sampling-based
> protocol: many older HPE/Aruba *ProVision* switches, Dell OS9/OS10, and the
> default mode on some Extreme/Ruckus gear). obserae cannot ingest sFlow. If
> that is all your device speaks, either enable **IPFIX** instead when the model
> supports it, or run a converter (`pmacct`, `sflowtool`, sFlow-RT) to translate
> sFlow into NetFlow and forward that to obserae. Likewise, **cloud VPC flow
> logs** (AWS, Azure, GCP) are a proprietary JSON format delivered to cloud
> storage, not NetFlow — they need a separate conversion pipeline, not a UDP
> collector.

---

## Routers & switches

### Cisco IOS / IOS-XE

Flexible NetFlow — NetFlow v5/v9 and IPFIX.
[Official docs](https://www.cisco.com/c/en/us/td/docs/routers/ios/config/17-x/ntw-servs/b-network-services/m_fnf-ipfix-export.html)

```cisco
flow exporter OBSERAE
 destination <obserae-host>
 transport udp 2055
 export-protocol netflow-v9        ! or: export-protocol ipfix  (transport udp 4739)

flow monitor OBSERAE-MON
 exporter OBSERAE
 record netflow ipv4 original-input

interface GigabitEthernet0/0/1
 ip flow monitor OBSERAE-MON input
```

### Juniper (Junos MX/EX, SRX)

J-Flow / inline flow monitoring — NetFlow v5/v9 and IPFIX.
[Official docs](https://www.juniper.net/documentation/en_US/junos/topics/topic-map/ipfix-formatting-for-srx-jflow.html)

```junos
set forwarding-options sampling instance JF family inet input rate 1000
set forwarding-options sampling instance JF family inet output flow-server <obserae-host> port 2055 version9
set forwarding-options sampling instance JF family inet output inline-jflow source-address <router-ip>
set interfaces ge-0/0/0 unit 0 family inet sampling input
```

For IPFIX use `version-ipfix` and port `4739`. One sampling instance per device;
sampled flows (not 1:1) — tune the `rate`.

### MikroTik RouterOS

Traffic Flow — NetFlow v1/v5/v9 and IPFIX.
[Official docs](https://help.mikrotik.com/docs/spaces/ROS/pages/21102653/Traffic+Flow)

```routeros
/ip traffic-flow set enabled=yes
/ip traffic-flow target add dst-address=<obserae-host> port=2055 version=9
```

Use `version=ipfix port=4739` for IPFIX. Traffic Flow only sees CPU-processed
traffic, not hardware-bridged traffic.

### More routers & switches

| Device | Protocols | Official docs |
|--------|-----------|---------------|
| Cisco Nexus (NX-OS) | NetFlow v9, IPFIX | [docs](https://www.cisco.com/c/en/us/td/docs/switches/datacenter/nexus9000/sw/104x/config-guides/cisco-nexus-9000-series-nx-os-system-management-configuration-guide-release-104x/m-configuring-netflow-104x.html) — set `transport udp 2055` (NX-OS default 9995 is a trap) |
| Cisco Meraki MX / MS | NetFlow v9 / IPFIX | [docs](https://documentation.meraki.com/SASE_and_SD-WAN/MX/Operate_and_Maintain/Monitoring_and_Reporting/NetFlow_Overview) |
| Huawei (NetStream, S1720, S2700, S5700, and S6720 V200R011C10) | NetFlow v5/v9, IPFIX | [docs](https://support.huawei.com/enterprise/en/doc/EDOC1000178174/e12db911/configuring-netstream-flexible-flow-statistics-exporting) |
| Arista EOS | IPFIX | [docs](https://www.arista.com/en/um-eos/eos-sampled-flow-tracking) |
| Nokia SR OS (Cflowd) | NetFlow v5/v8/v9, IPFIX | [docs](https://documentation.nokia.com/html/0_add-h-f/93-0073-10-01/7750_SR_OS_Router_Configuration_Guide/Cflowd_cli.html) |
| Extreme EXOS / VOSS | NetFlow v9, IPFIX (also sFlow) | [docs](https://documentation.extremenetworks.com/exos_31.4/GUID-28A71D0E-9F56-459C-B339-70B02A8D3D62.shtml) |
| HPE Aruba (ArubaOS-CX) | IPFIX | [docs](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.15/HTML/monitoring_8100-83xx-9300-10000/Content/Chp_flow/conf-ipfix.htm) — ProVision/ArubaOS-Switch is sFlow-only |
| VyOS | NetFlow v5/v9, IPFIX | [docs](https://docs.vyos.io/en/latest/configuration/system/flow-accounting.html) |
| Ubiquiti EdgeRouter (EdgeOS) | NetFlow v5/v9, IPFIX | [docs](https://help.uisp.com/hc/en-us/articles/22590965913239-UISP-NetFlow) |
| Ubiquiti UniFi Gateway | NetFlow v5/v9, IPFIX | [docs](https://help.ui.com/articles/3932726-UniFi-Dream-Machine-Traffic-Flow-Export) |
| Allied Telesis (AlliedWare Plus) | IPFIX | [docs](https://www.alliedtelesis.com/us/en/documents/ipfix-feature-overview-and-configuration-guide) |
| Ruckus / Brocade ICX | NetFlow v9, IPFIX (FastIron 09.x) | [docs](https://support.ruckuswireless.com/documents/4026-fastiron-09-0-10-ga-command-reference-guide) — sFlow on older firmware |

---

## Firewalls & UTM

### FortiGate / FortiOS

NetFlow v9 (and v5). NetFlow is enabled per interface.
[Official docs](https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/31620/config-system-netflow)

```fortios
config system netflow
  set collector-ip <obserae-host>
  set collector-port 2055
end
config system interface
  edit "port1"
    set netflow-sampler both
  next
end
```

### Palo Alto PAN-OS

NetFlow v9.
[Official docs](https://docs.paloaltonetworks.com/ngfw/administration/monitoring/netflow-monitoring/configure-netflow-exports)

In the GUI: **Device → Server Profiles → NetFlow**, add a profile with server
`<obserae-host>` and port `2055`, then assign that profile to each ingress
interface under **Network → Interfaces**.

### pfSense

NetFlow v5/v9 and IPFIX.
[Official docs (pflow)](https://docs.netgate.com/pfsense/en/latest/firewall/pflow.html)

- **pfSense Plus 24.03+**: *Firewall → Packet Flow Data (pflow)* → add an
  exporter, Collector `<obserae-host>`, Port `2055` (NetFlow) or `4739` (IPFIX).
- **Older / Community Edition**: install the `softflowd` package (*System →
  Package Manager*), then *Services → softflowd*: Host `<obserae-host>`, Port
  `2055`, version `9`.

### OPNsense

NetFlow v5/v9.
[Official docs](https://docs.opnsense.org/manual/how-tos/netflow_exporter.html)

In the GUI: **Reporting → NetFlow** → select the interfaces to watch, set
Version `9`, and add the destination `<obserae-host>:2055`.

### More firewalls & UTM

| Device | Protocols | Official docs |
|--------|-----------|---------------|
| Cisco ASA | NetFlow v9 / NSEL | [docs](https://www.cisco.com/c/en/us/support/docs/security/asa-5500-x-series-next-generation-firewalls/119959-config-asa-00.html) |
| Juniper SRX | NetFlow v5/v9, IPFIX | [docs](https://www.juniper.net/documentation/en_US/junos/topics/topic-map/ipfix-formatting-for-srx-jflow.html) |
| Check Point (Gaia) | NetFlow v5/v9, IPFIX | [docs](https://sc1.checkpoint.com/documents/R80.20_GA/WebAdminGuides/EN/CP_R80.20_Gaia_AdminGuide/207090.htm) |
| SonicWall (SonicOS AppFlow) | NetFlow v5/v9, IPFIX | [docs](https://www.sonicwall.com/support/knowledge-base/netflow-version-9-configuration-procedures-5-8-onwards/kA1VN0000000ID40AM) |
| Sophos Firewall (SFOS) | NetFlow v5 | [docs](https://docs.sophos.com/nsg/sophos-firewall/21.5/Help/en-us/webhelp/onlinehelp/AdministratorHelp/Administration/NetflowConfiguration/index.html) |
| WatchGuard Firebox | NetFlow v5/v9 | [docs](https://www.watchguard.com/help/docs/help-center/en-US/Content/en-US/Fireware/basicadmin/netflow_configure.html) |
| Barracuda CloudGen Firewall | NetFlow v5/v9, IPFIX | [docs](https://campus.barracuda.com/product/cloudgenfirewall/doc/73698835/netflow-export-configuration/) |
| F5 BIG-IP (AFM/AVR) | NetFlow v9, IPFIX | [docs](https://techdocs.f5.com/kb/en-us/products/big-ip-afm/manuals/product/network-firewall-policies-implementations-11-6-0/16.html) — its sFlow is system monitoring only; use IPFIX/NetFlow for flow export |

---

## Host & software probes

Run a probe on a server or a SPAN/mirror port when the device itself can't
export flows.

### softflowd

Reads a libpcap interface, exports NetFlow v1/v5/v9 or IPFIX.
[Official docs](https://github.com/irino/softflowd/wiki/softflowd)

```sh
softflowd -i eth0 -v 9  -n <obserae-host>:2055     # NetFlow v9
softflowd -i eth0 -v 10 -n <obserae-host>:4739     # IPFIX
```

### pmacct (nfprobe plugin)

Capture daemon (`pmacctd` / `uacctd`) with the built-in `nfprobe` plugin.
[Official docs (CONFIG-KEYS)](https://github.com/pmacct/pmacct/blob/master/CONFIG-KEYS)

```ini
# pmacctd.conf
pcap_interface: eth0
plugins: nfprobe
nfprobe_receiver: <obserae-host>:2055
nfprobe_version: 9          # 5, 9, or 10 (IPFIX → use :4739)
aggregate: src_host, dst_host, src_port, dst_port, proto
```

### More host probes

| Probe | Protocols | Official docs |
|-------|-----------|---------------|
| fprobe / fprobe-ng | NetFlow v1/v5/v7 | [man page](https://manpages.ubuntu.com/manpages/jammy/man8/fprobe.8.html) |
| nProbe (ntop) | NetFlow v5/v9, IPFIX | [docs](https://www.ntop.org/guides/nprobe/cli_options.html) |
| ipt-NETFLOW (Linux kernel module) | NetFlow v5/v9, IPFIX | [docs](https://github.com/aabc/ipt-netflow/blob/master/README) |
| YAF (CERT NetSA) | IPFIX | [docs](https://tools.netsa.cert.org/yaf/docs.html) |
| ulogd2 (Netfilter) | IPFIX | [man page](https://manpages.debian.org/bookworm/ulogd2/ulogd.8.en.html) |

---

## Virtual & cloud switches

### Open vSwitch (OVS)

NetFlow v5 and IPFIX (per bridge).
[Official docs (ovs-vsctl)](https://www.man7.org/linux/man-pages/man8/ovs-vsctl.8.html)

```sh
# NetFlow v5
ovs-vsctl -- set Bridge br0 netflow=@nf -- \
  --id=@nf create NetFlow targets='"<obserae-host>:2055"' active-timeout=60

# IPFIX
ovs-vsctl -- set Bridge br0 ipfix=@i -- \
  --id=@i create IPFIX targets='"<obserae-host>:4739"'
```

### More virtual switches

| Platform | Protocols | Official docs |
|----------|-----------|---------------|
| VMware vSphere Distributed Switch | IPFIX | [docs](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/9-0/vsphere-networking/monitoring-network-packets/configure-netflow-settings-with-the-vsphere-web-client.html) |

---

## Verifying it works

Once a device is exporting, watch the `flows` counter climb:

```sh
./obserae-cli --socket ./data/obserae.sock status
```

If after a couple of minutes the counter stays at `0`:

- **Is the listener up?** `sudo ss -ulnp | grep -E '2055|4739'`
- **Is anything arriving?** `sudo tcpdump -ni any udp port 2055 -c 5`
  (use `4739` for IPFIX).

> **NetFlow v9 / IPFIX template warm-up.** These protocols send a *template*
> describing the record layout separately from the data, and only every so
> often (often every 20 packets or every 30 minutes, depending on the device).
> Until obserae receives that first template, the matching flows can't be
> decoded — so a brand-new exporter can show traffic in `tcpdump` while the
> counter is still `0`. Wait for the next template, or force a refresh on the
> device. NetFlow v5 has no templates and decodes immediately.

If `tcpdump` shows packets but the counter never moves even after the template
window, check the daemon log — it prints decode errors at the default verbosity.

---

## Next steps

- [sources.md](sources.md) — give each exporter a friendly name in the GUI.
- [quickstart.md](quickstart.md) — your first cartography, rules and query.
- [configuration.md](configuration.md) — change the listener ports or disable a
  protocol.
