![GitHub License](https://img.shields.io/github/license/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) ![GitHub Downloads](https://img.shields.io/github/downloads/CHKayanami/OpenWrt-nikki-rs/total?style=for-the-badge&logo=github) ![GitHub Stars](https://img.shields.io/github/stars/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) [![Telegram](https://img.shields.io/badge/Telegram-gray?style=for-the-badge&logo=telegram)](https://t.me/OpNikkiRS)

English | [中文](README.zh.md)

# Nikki RS

**Nikki RS** is a fork of [OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) for OpenWrt. It integrates [clash-rs](https://github.com/Watfaq/clash-rs), a high-performance proxy core written in Rust, providing a lightweight and high-performance transparent proxy solution for OpenWrt.

---

## Features & Highlights

- **Out of the Box**: Built-in default firewall rules (FakeIP + bypass mainland China) and routing rules to meet most common scenarios. Also supports easy configuration for custom nodes—just configure your proxy node details to get started.
- **Ultra Lightweight (`clash-rs`)**: Powered by a fork of [clash-rs](https://github.com/CHKayanami/clash-rs) written in Rust, significantly reducing memory and CPU overhead. Compared to the original version, it fixes several bugs, adds new features, and improves stability.
- **Configuration Compatibility**: Most configurations are compatible with mihomo. Unsupported options will not cause errors—they simply will not take effect. For details, refer to [clash-rs configuration](https://github.com/CHKayanami/clash-rs/blob/master/clash-bin/tests/data/config/full.yaml).
- **Transparent Proxy**: Native support for Redirect and TPROXY modes, covering both IPv4 and IPv6 traffic routing. (Note: The UI retains TUN mode options, but the default built-in kernel is `minimal` and does not include the TUN module. If you need TUN mode or full protocol support, you can switch to the `standard` release).
- **Rich Protocol Support**: Excellent support for protocols including SS, AnyTLS, Hysteria2 (hy2), and VLESS-Vision-Reality. Modules such as SSH, WireGuard, Tailscale, Shadowquic, and Tor are removed in the default kernel. You can quickly switch between `minimal` and `standard` cores using the one-click script:
  ```bash
  wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/switch_core.sh | ash
  ```
- **Streamlined Configuration**: Adapted to the core features of `clash-rs` by removing unsupported redundant configuration items, making the interface cleaner and easier to use.

---

## Prerequisites

- **OpenWrt** >= 24.10
- **Linux Kernel** >= 5.13
- **firewall4** (nftables based)

---

## Quick Start

### Option A: Install from Feed (Recommended)

1. **Add Feed**:
   ```bash
   wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/feed.sh | ash
   ```

2. **Install Packages**:
   - **opkg**:
     ```bash
     opkg update
     opkg install nikki-rs luci-app-nikki-rs luci-i18n-nikki-rs-zh-cn
     ```
   - **apk**:
     ```bash
     apk update
     apk add nikki-rs luci-app-nikki-rs luci-i18n-nikki-rs-zh-cn
     ```

### Option B: One-Click Installation from Release

```bash
wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/install.sh | ash
```

### Basic Setup

1. Open OpenWrt LuCI Web Interface.
2. Navigate to **Services** -> **Nikki RS**.
3. Import subscription link or configuration profile, and enable the transparent proxy service.

---

## Uninstall & Reset

```bash
wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/uninstall.sh | ash
```

---

## Compilation

To compile `nikki-rs` in your OpenWrt source code or SDK:

```bash
# Add feed source
echo "src-git nikki-rs https://github.com/CHKayanami/OpenWrt-nikki-rs.git;main" >> "feeds.conf.default"

# Update and install feeds
./scripts/feeds update -a
./scripts/feeds install -a

# Compile package
make package/luci-app-nikki-rs/compile
```

The compiled ipk / apk packages are located in `bin/packages/<arch>/nikki-rs`.

---

## Dependencies

- `ca-bundle`
- `curl`
- `yq`
- `firewall4`
- `ip-full`
- `kmod-inet-diag`
- `kmod-nft-socket`
- `kmod-nft-tproxy`
- `kmod-tun`
- `kmod-dummy`

---

## Credits

Sincere thanks to the contributions from upstream projects and open source developers:

- **[nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)** ([@nikkinikki-org](https://github.com/nikkinikki-org)): For designing and maintaining the OpenWrt LuCI interface and transparent proxy infrastructure.
- **[clash-rs](https://github.com/Watfaq/clash-rs)**: For developing the exceptional, lightweight, and high-performance Clash proxy core written in Rust.


