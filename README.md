# BrightSpeed XG2010G · 刷机与 IPTV 修复分享包

> Gemtek / BrightSpeed **XG2010G**（Airoha AN7581）的固件刷写说明 + IPTV 组播修复补丁。

---

## ⚠️ 测试环境声明（请先看这一段）

**本包的全部实测数据与修复方案，只在中国电信四川（成都）10G-EPON 线路上验证过：**

| 项目 | 实测值 |
|---|---|
| 运营商 | 中国电信 · 四川（成都） |
| 接入方式 | 10G-EPON |
| 签约带宽 | 2000 Mbps |
| 上网 VLAN | PPPoE 桥接，由下游路由器拨号 |
| IPTV | 单播 VLAN + 组播 VLAN，机顶盒接 LAN3 |

**其他运营商、其他省份、GPON / XG-PON / 其他 VLAN 规划、其他机顶盒型号，均未做任何测试。**

- 上网/桥接部分理论上与运营商无关（PPPoE 桥接是标准行为），但仍需你自行验证。
- **IPTV 补丁是针对"VLAN 子接口做桥端口 + IGMP 组播"这个具体拓扑写的**，如果你的线路结构不同，可能完全用不上，也可能需要调整。
- 语音（VoIP）部分**未完成**，不要指望刷完能打电话。

风险自负。刷机前请确认自己有能力通过串口或 U-Boot 救回来。

---

## 一、包含内容

| 文件 | 说明 |
|---|---|
| `刷机说明.md` | 详细刷机步骤、补丁安装、故障恢复 |
| `install-iptv-fix.sh` | IPTV 补丁安装脚本（在光猫上执行） |
| `iptv-fix/` | IPTV 补丁源文件（4 个文件） |
| `sha256sums` | 全部文件校验值 |

**固件本体（89.34 MiB `.itb`）和完整打包 zip 在 [Releases](../../releases) 页面下载** ——
固件是二进制大文件，不放仓库里，避免 clone 臃肿。

固件来源：[naoki66/ImmortalWrt-for-Gemtek-brightspeed](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed)
release `20261115`（提交 `5e152df9`），**原样未修改**，sha256 与发布页一致。

---

## 二、为什么固件和补丁分开

官方 `.itb` 是**签名镜像**，改了内容验签就失败、刷不进去。
所以：固件保持官方原样，补丁单独安装。

装完效果和"一体化固件"完全一样，而且：

- 官方出升级版时，你不会因为"自己改过镜像"而卡住
- 补丁文件都写进了 `/etc/sysupgrade.conf`，升级固件时会自动保留

---

## 三、实测结果

同一条线路、同一台设备、同样的测速环境：

| 固件版本 | 下行速率 | 说明 |
|---|---|---|
| 20261010 及更早 | 722~747 Mbps | 桥接模式无 NPU 卸载，NET_RX 全压在 cpu0 |
| **20261115** | **2547.76 Mbps** | 675-* 补丁实现桥接 flowtable 硬件卸载 |

```
测速平台   四川电信官方测速（speed.sc.189.cn）
签约       2000 Mbps
实测下行   2547.76 Mbps  (127%)
实测上行   57.38 Mbps    (运营商 60M 硬限，非设备问题)
PPE 对账   硬件转发 5,964,767,381 B ≈ lan1 实际发送 5,981,177,466 B（差 0.3%）
CPU        各核个位数占用，几乎空闲
丢包       零丢包、零错包、零 MIB overrun
```

**结论：这台设备的桥接带宽从来不是板级限制，之前跑不满是固件缺桥接卸载功能。**

---

## 四、快速开始

### 1. 刷固件

```
前提：已刷 OpenWrt 专用 U-Boot，compat_version = 2.0，原厂固件不能直刷

下载 Release 里的 .itb → LuCI「系统 → 备份/升级」
  → 选文件 → 必须取消勾选「保留配置」 → 刷写
```

> 新版与旧版配置不兼容，**务必 `sysupgrade -n`**。

### 2. 配置 PON 与网络

```
LuCI「网络 → ONU」：填自己的 LOID、认证方式、运营商、PON 模式
LuCI「网络 → 接口」：按自己线路的 VLAN 规划建桥
```

### 3. 装 IPTV 补丁（如果你的 IPTV 卡顿/卡 85%）

```sh
scp -r iptv-fix install-iptv-fix.sh root@<光猫IP>:/tmp/
ssh root@<光猫IP> 'cd /tmp && sh install-iptv-fix.sh'
```

装完**换一次台**，过滤会自动收敛到当前频道。

详见 [刷机说明.md](刷机说明.md)。

---

## 五、IPTV 补丁解决的两个问题

### 问题一：机顶盒卡在 85%

```
根因  IPTV 网关 MAC 同时学在单播 VLAN 口和组播 VLAN 口上（组播流的源 MAC 就是它）
      桥不感知 VLAN → FDB 只有一份 → 学到组播口
      → 机顶盒发往网关的单播包被转进组播 VLAN，再被 nft 规则丢弃
证据  lan3 → 组播 VLAN 的 drop 计数持续增长，单播 VLAN 上行长期为 0
修复  组播 VLAN 端口关闭 MAC 学习
```

### 问题二：所有频道卡顿、4K 马赛克

```
根因  内核桥的 IGMP snooping 对「VLAN 子接口当桥端口」的拓扑不工作
      · MDB 里登记不进电视频道组
      · 手工 bridge mdb add 之后转发仍然是 0
      → igmp_snooping=1 名存实亡，只能泛洪
      → PON 上全部 9 个频道约 90 Mbps 全推给机顶盒
      → 4K 频道（25.5 Mbps）尤其吃不消 → 马赛克
已排除  精确计数器显示 PON 进 246,527 包 → lan3 出 246,527 包，差 0（光猫零丢包）
修复  自建 userspace snooper + nftables 集合
      阶段1 启动时放行所有在传组播组 → 画面立即可用
      阶段2 监听机顶盒 IGMP 报告 → 收敛为当前频道组，换台自动跟随
效果  lan3 由 90 Mbps 降到 9~26 Mbps
```

---

## 六、已知限制

- **语音（VoIP）未完成**：`omcid` 不支持 OMCI 语音下发（`strings omcid | grep -iE 'voice|voip|sip|h248'` 零命中），
  必须手工填 SIP 服务器/用户名/密码。硬件与 asterisk 已就绪。
- **桥接加速依赖 `bridge-nf-filter-pppoe-tagged=1`**，为 0 时带宽会掉回 1G 以下。
- IPTV 补丁依赖机顶盒**会发 IGMP 报告**；极少数机顶盒不发的话会一直走泛洪（能看但占带宽）。
- 组播过滤在**重启后先进入泛洪待命**，需要换一次台才收敛，这是设计行为。

---

## 七、致谢

- [naoki66](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed) —— 20261115 版把桥接 NPU 卸载做出来了，这是 2547 Mbps 的根本原因
- pbs05 —— PonWrt 与 U-Boot 基础工作
- 上游 ImmortalWrt / OpenWrt 社区

## 八、许可

本仓库的脚本与文档：MIT。
固件本体版权归原作者，请遵循其仓库的许可。

---

**再次强调：只有中国电信四川 10G-EPON 环境验证过，其他环境请自行测试并承担风险。**
