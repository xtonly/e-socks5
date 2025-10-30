#!/bin/bash

# =================================================================
# Debian/Ubuntu 一键安装 Dante SOCKS5 代理脚本
# (高位端口 58998, 用户名 'guest', 带密码认证)
# =================================================================

# 0. 定义变量 (已按您的要求修改)
DANTE_PORT="58998"
PROXY_USER="guest"
# 生成一个 16 位的随机密码
PROXY_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo "错误：此脚本必须以 root 权限运行。" 1>&2
   exit 1
fi

echo "正在开始安装和配置 Dante SOCKS5 代理..."

# 1. 更新并安装 Dante 服务器和依赖
apt update
apt install -y dante-server

# 2. 创建一个专用的系统用户来运行 dante (更安全)
if ! id "socksuser" &>/dev/null; then
    useradd --shell /usr/sbin/nologin --no-create-home socksuser
    echo "创建专用系统用户 'socksuser' 完成。"
else
    echo "系统用户 'socksuser' 已存在。"
fi

# 3. 创建用于 SOCKS 认证的用户和密码
# 注意：这是 Linux 系统用户，但 dante 会用 pam 来认证它
if ! id "$PROXY_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin $PROXY_USER
    echo "创建代理认证用户 '$PROXY_USER' 完成。"
else
    echo "代理认证用户 '$PROXY_USER' 已存在。"
fi

# 为该用户设置密码
echo "$PROXY_USER:$PROXY_PASS" | chpasswd
echo "为 '$PROXY_USER' 设置随机密码完成。"

# 4. 备份并创建 dante 配置文件
DANTE_CONFIG="/etc/danted.conf"
if [ -f "$DANTE_CONFIG" ]; then
    mv $DANTE_CONFIG "${DANTE_CONFIG}.bak_$(date +%Y%m%d%H%M%S)"
    echo "备份旧配置文件为 ${DANTE_CONFIG}.bak_..."
fi

# 获取服务器的主网络接口 (例如 eth0)
INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    echo "警告：无法自动检测网络接口。将尝试监听所有接口。"
    LISTEN_ON="0.0.0.0"
else
    echo "自动检测到网络接口为: $INTERFACE"
    LISTEN_ON=$(ip -4 addr show $INTERFACE | grep 'inet' | awk '{print $2}' | cut -d'/' -f1)
fi

# 写入新的配置文件
cat > $DANTE_CONFIG << EOF
# /etc/danted.conf
# -----------------

# 日志设置
logoutput: /var/log/danted.log

# 监听的 IP 和 端口 (已修改为 58998)
internal: $LISTEN_ON port = $DANTE_PORT

# 绑定的出口 IP (使用与 internal 相同的接口)
external: $INTERFACE

# 运行服务的用户 (非 root)
user.privileged: root
user.unprivileged: socksuser

# --- 认证方法 ---
# 使用标准 PAM 认证 (即 /etc/passwd 和 /etc/shadow)
socksmethod: username

# --- 访问控制 ---

# 1. 允许来自任何地方 (0.0.0.0/0) 的认证用户
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# 2. 允许认证用户连接到任何地方
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    # 'username' 意思是必须经过认证
    socksmethod: username
    log: error connect disconnect
}
EOF

echo "Dante 配置文件创建完成。"

# 5. 重启 dante 服务并设置开机自启
systemctl restart danted
systemctl enable danted

# 6. 检查服务状态
if systemctl is-active --quiet danted; then
    echo "Dante 服务已成功启动。"
else
    echo "错误：Dante 服务启动失败。"
    echo "请运行 'systemctl status danted' 和 'journalctl -xe' 查看详细日志。"
    exit 1
fi

# 7. 显示连接信息
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "====================================================="
echo "✅ SOCKS5 代理服务器安装配置完成！"
echo ""
echo "  服务器 IP (Server IP): $SERVER_IP"
echo "  端口 (Port):         $DANTE_PORT"
echo "  用户名 (Username):   $PROXY_USER"
echo "  密 码 (Password):    $PROXY_PASS"
echo ""
echo "  配置文件位于: $DANTE_CONFIG"
echo "  日志文件位于: /var/log/danted.log"
echo "====================================================="
