#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 ---
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

if [ "$USER_NAME" = "root" ]; then
    TARGET_HOME="/root"
else
    TARGET_HOME="/home/$USER_NAME"
fi

# --- 2. 动态创建用户 ---
if [ "$USER_NAME" != "root" ]; then
    if ! id -u "$USER_NAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$USER_NAME" || true
    fi
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$TARGET_HOME"
fi

echo "root:$USER_PWD" | chpasswd
[ "$USER_NAME" != "root" ] && echo "$USER_NAME:$USER_PWD" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users

# --- 3. 处理配置模板 ---
BOOT_DIR="$TARGET_HOME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$BOOT_DIR"
fi

# --- 4. 动态进程控制与保活激活 ---

# Cloudflared 判断
if [ -z "$CF_TOKEN" ]; then
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/' "$BOOT_CONF"
else
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# 【强制激活保活脚本】不再判断变量，脚本内部有兜底
echo "💓 激活 Keepalive 守护进程..."
sed -i '/\[program:keepalive\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"

# ttyd 处理
if [ -n "$TTYD" ]; then
	sed -i "s|/usr/local/bin/ttyd -W bash|/usr/local/bin/ttyd -c $TTYD -W bash|g" "$BOOT_CONF"
fi

# --- 5. 修复 sctl 快捷指令 (解决 localhost:9001 报错) ---
alias_cmd="alias sctl='supervisorctl -c $BOOT_CONF'"
echo "$alias_cmd" >> /etc/bash.bashrc
echo "$alias_cmd" >> /root/.bashrc
[ -f "$TARGET_HOME/.bashrc" ] && echo "$alias_cmd" >> "$TARGET_HOME/.bashrc"

# --- 6. 启动 ---
if [ -n "$SSH_CMD" ]; then
    exec /bin/sh -c "$SSH_CMD"
else
    # 显式使用生成的配置文件启动
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
