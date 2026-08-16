![GitHub License](https://img.shields.io/github/license/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) ![GitHub Downloads](https://img.shields.io/github/downloads/CHKayanami/OpenWrt-nikki-rs/total?style=for-the-badge&logo=github) ![GitHub Stars](https://img.shields.io/github/stars/CHKayanami/OpenWrt-nikki-rs?style=for-the-badge&logo=github) [![Telegram](https://img.shields.io/badge/Telegram-gray?style=for-the-badge&logo=telegram)](https://t.me/OpNikkiRS)

中文 | [English](README.md)

# Nikki RS

**Nikki RS** 是基于 [OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) 的 OpenWrt Fork 分支。本项目集成了由 Rust 编写的高性能代理核心 [clash-rs](https://github.com/Watfaq/clash-rs)，为 OpenWrt 提供轻量、高性能的透明代理解决方案。

---

## 项目特色
- **开箱即用**：内置预设防火墙规则（FakeIP + 绕过大陆）与分流策略，满足绝大多数常见使用场景，同时支持便捷的自建节点配置，只需要配置代理节点信息就可开始使用。
- **极致轻量 (`clash-rs`)**：基于 Rust 编写的 [clash-rs](https://github.com/CHKayanami/clash-rs) Fork 版本核心，极大幅度降低内存占用与 CPU 开销；相比原版修复了多项 Bug、扩充了一些功能并提升了运行稳定性。
- **配置兼容**：配置绝大部分兼容mihomo，部分配置不支持的也不会报错，只是不会生效，具体配置参考[clash-rs配置](https://github.com/CHKayanami/clash-rs/blob/master/clash-bin/tests/data/config/full.yaml)
- **透明代理**：原生支持 Redirect 、 TPROXY 和 TUN 模式，完整覆盖 IPv4 与 IPv6 流量分流。
- **丰富协议支持**：良好支持 SS、AnyTLS、Hysteria2 (hy2) 及 VLESS-Vision-Reality 等协议；默认内核移除了 SSH、WireGuard、Tailscale、Shadowquic、Tor 等模块，可通过一键脚本快速切换为完整版内核：
  ```bash
  wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/switch_core.sh | ash
  ```
- **配置精简**：针对 `clash-rs` 的核心特性进行了适配，移除了不支持的冗余配置项，使控制界面更加纯粹易用。
---

## 环境要求

- **OpenWrt** >= 24.10
- **Linux Kernel** >= 5.13
- **firewall4** (基于 nftables)

---

## 快速使用

### 方式 A：从软件源安装（推荐）

1. **添加软件源**：
   ```bash
   wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/feed.sh | ash
   ```

2. **安装软件包**：
   - **opkg**：
     ```bash
     opkg update
     opkg install nikki-rs luci-app-nikki-rs luci-i18n-nikki-rs-zh-cn
     ```
   - **apk**：
     ```bash
     apk update
     apk add nikki-rs luci-app-nikki-rs luci-i18n-nikki-rs-zh-cn
     ```

### 方式 B：从 Release 一键安装

```bash
wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/install.sh | ash
```

### 快速配置

1. 打开 OpenWrt LuCI 后台。
2. 导航至 **服务 (Services)** -> **Nikki RS**。
3. 导入订阅链接或配置文件，启动透明代理服务。

---

## 卸载与重置

```bash
wget -O - https://github.com/CHKayanami/OpenWrt-nikki-rs/raw/refs/heads/main/uninstall.sh | ash
```

---

## 编译指南

如需在 OpenWrt 源码或 SDK 中自行编译 `nikki-rs`：

```bash
# 添加 feed 软件源
echo "src-git nikki-rs https://github.com/CHKayanami/OpenWrt-nikki-rs.git;main" >> "feeds.conf.default"

# 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 编译软件包
make package/luci-app-nikki-rs/compile
```

编译生成的 ipk / apk 文件位于 `bin/packages/<架构>/nikki-rs` 路径下。

---

## 软件包依赖

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

## 致谢 (Credits)

非常感谢上游项目及开源社区优秀开发者的贡献：

- **[nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)** ([@nikkinikki-org](https://github.com/nikkinikki-org))：感谢 nikki 项目团队设计并维护了 OpenWrt LuCI 界面与透明代理基础架构。
- **[clash-rs](https://github.com/Watfaq/clash-rs)**：感谢开发团队用 Rust 打造了高性能、轻量且强大的 Clash 代理内核。


