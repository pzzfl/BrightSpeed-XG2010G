#!/bin/sh
# XG2010G IPTV 修复补丁 · 安装脚本
# 用法（在光猫上执行）：
#   cd /tmp && sh install-iptv-fix.sh
#
# 作用：
#   1) 关闭 br-iptv 的 IGMP snooping（内核 snooping 对 VLAN 子接口端口不工作）
#   2) 关闭组播 VLAN 端口的 MAC 学习（否则单播 FDB 会被组播源 MAC 污染，
#      机顶盒卡在 85%）
#   3) 安装动态组播过滤守护进程，只把当前频道推给机顶盒
#
# 卸载：/etc/init.d/zz-iptv-snoop disable; /etc/init.d/zz-iptv-fix disable
#       然后删除 /etc/init.d/zz-iptv-* /usr/libexec/iptv-snoop /etc/iptv-snoop.nft

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== 检查环境 =="
[ -d /sys/class/net/br-iptv ] || echo "  [!] 当前没有 br-iptv —— 请先在 LuCI「网络 → ONU → IPTV」启用桥接模式"
command -v nft >/dev/null || { echo "  [x] 缺少 nft"; exit 1; }
command -v tcpdump >/dev/null || { echo "  [x] 缺少 tcpdump"; exit 1; }

echo "== 复制文件 =="
cp -f "$HERE/iptv-fix/etc/init.d/zz-iptv-fix"   /etc/init.d/zz-iptv-fix   && chmod 755 /etc/init.d/zz-iptv-fix
cp -f "$HERE/iptv-fix/etc/init.d/zz-iptv-snoop" /etc/init.d/zz-iptv-snoop && chmod 755 /etc/init.d/zz-iptv-snoop
cp -f "$HERE/iptv-fix/usr/libexec/iptv-snoop"   /usr/libexec/iptv-snoop   && chmod 755 /usr/libexec/iptv-snoop
cp -f "$HERE/iptv-fix/etc/iptv-snoop.nft"       /etc/iptv-snoop.nft       && chmod 644 /etc/iptv-snoop.nft
echo "  ✔ 4 个文件已就位"

echo "== 加入 sysupgrade 保留列表 =="
for f in /etc/init.d/zz-iptv-fix /etc/init.d/zz-iptv-snoop /usr/libexec/iptv-snoop /etc/iptv-snoop.nft; do
	grep -qx "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
done
echo "  ✔ 升级固件时会保留"

echo "== 启用并立即应用 =="
/etc/init.d/zz-iptv-fix enable
/etc/init.d/zz-iptv-snoop enable
/etc/init.d/zz-iptv-fix start
/etc/init.d/zz-iptv-snoop start

sleep 3
echo
echo "== 结果 =="
echo "  multicast_snooping = $(cat /sys/class/net/br-iptv/bridge/multicast_snooping 2>/dev/null)  (应为 0)"
echo "  ct-iptv-mc learning = $(cat /sys/class/net/ct-iptv-mc/brport/learning 2>/dev/null)  (应为 0)"
echo "  snooper 进程 = $(pgrep -f iptv-snoop | tr '\n' ' ')"
echo
echo "完成。接下来请做两件事："
echo "  1) 机顶盒断电重启一次（如果之前卡在 85%）"
echo "  2) 用遥控器换一次台 —— 这一步很重要："
echo "     安装后默认是「泛洪待命」状态（所有频道都推给机顶盒，能看但占带宽）；"
echo "     换台时守护进程会捕获 IGMP 报告，自动收敛到只发当前频道，卡顿才会消失。"
echo "     之后每次换台都会自动跟随。"
echo "  查看状态：logread | grep iptv-snoop"
echo "  查看放行：nft list set bridge iptv_snoop subs"
