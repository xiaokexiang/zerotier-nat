#!/bin/bash

# 定义默认的脚本路径
DEFAULT_SCRIPT_PATH="/root/zerotier-nat.sh"

# 检查 iptables 依赖
if ! command -v iptables &> /dev/null; then
    echo "Error: iptables is not installed. Please install it first."
    exit 1
fi

# 检查 ovs-vsctl 依赖
if command -v ovs-vsctl &> /dev/null; then
    # 获取物理网卡名称，优先选择 OVS 网卡
    PHY_IFACE=$(ovs-vsctl list-br | head -n 1)
else
    echo "Warning: ovs-vsctl is not installed. Will use non-OVS method to get physical interface."
    PHY_IFACE=""
fi

if [ -z "$PHY_IFACE" ]; then
    PHY_IFACE=$(ip link show | awk '/^[0-9]+:/{if (count++ == 1) print $2;}' | sed 's/:$//')
fi

# 获取 Zerotier 虚拟网卡名称
ZT_IFACE=$(ip a | grep 'zt' | awk 'NR==2 {print $NF}')

# 输出获取的网卡名称
echo "Physical Interface: $PHY_IFACE"
echo "Zerotier Interface: $ZT_IFACE"

# 处理路径，若为目录则添加默认文件名
handle_path() {
    local path="$1"
    if [ -d "$path" ]; then
        echo "$path/zerotier-nat.sh"
    else
        echo "$path"
    fi
}

# 函数：添加 iptables 规则
start() {
    SCRIPT_PATH=$(handle_path "${2:-$DEFAULT_SCRIPT_PATH}")
    echo "Starting network rules..."
    sudo iptables -t nat -A POSTROUTING -o "$PHY_IFACE" -j MASQUERADE
    sudo iptables -A FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT
    echo "iptables rules have been set."
}

# 函数：删除 iptables 规则
stop() {
    SCRIPT_PATH=$(handle_path "${2:-$DEFAULT_SCRIPT_PATH}")
    echo "Stopping network rules..."
    sudo iptables -t nat -D POSTROUTING -o "$PHY_IFACE" -j MASQUERADE
    sudo iptables -D FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -D FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT
    echo "iptables rules have been removed."
}

# 函数：重载 iptables 规则
reload() {
    SCRIPT_PATH=$(handle_path "${2:-$DEFAULT_SCRIPT_PATH}")
    echo "Reloading network rules..."
    stop "$1" "$2"
    start "$1" "$2"
    echo "iptables rules have been reloaded."
}

install() {
    SCRIPT_PATH=$(handle_path "${2:-$DEFAULT_SCRIPT_PATH}")
    # 将脚本自身复制到指定路径
    CURRENT_SCRIPT_PATH=$(realpath "$0")
    sudo cp "$CURRENT_SCRIPT_PATH" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"

    # 创建 systemd 服务
    sudo bash -c "cat > /etc/systemd/system/zerotier-nat.service << EOF
[Unit]
Description=Run zerotier nat at startup
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_PATH start
ExecStop=/bin/bash $SCRIPT_PATH stop
ExecReload=/bin/bash $SCRIPT_PATH reload
PIDFile=/var/run/zerotier-nat.pid
Restart=on-failure
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable zerotier-nat.service
    sudo systemctl start zerotier-nat.service
}

uninstall() {
    SCRIPT_PATH=$(handle_path "${2:-$DEFAULT_SCRIPT_PATH}")
    echo "Stopping and disabling zerotier-nat service..."
    sudo systemctl stop zerotier-nat.service
    sudo systemctl disable zerotier-nat.service

    echo "Removing systemd service file..."
    sudo rm -f /etc/systemd/system/zerotier-nat.service

    echo "Removing script file..."
    sudo rm -f "$SCRIPT_PATH"

    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    echo "zerotier-nat service has been uninstalled."
}

# 检查参数并调用相应的函数
case "$1" in
    start)
        start "$1" "$2"
        ;;
    stop)
        stop "$1" "$2"
        ;;
    reload)
        reload "$1" "$2"
        ;;
    install)
        install "$1" "$2"
        ;;
    uninstall)
        uninstall "$1" "$2"
        ;;
    *)
        echo "Usage: $0 {start|stop|reload|install|uninstall} [script_path]"
        exit 1
        ;;
esac
