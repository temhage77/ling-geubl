FROM ubuntu:22.04

# 1. 基础环境设置
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=105106

# 2. 安装必要软件包
RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    tzdata vmin net-tools unzip iputils-ping telnet git iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装工具 (cloudflared & ttyd)
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 4. 写入集成版保活脚本 (包含变量识别 + 你的硬编码地址兜底)
RUN cat <<'EOF' > /usr/local/bin/keepalive.sh
#!/bin/bash
# 优先级：1. 环境变量 E_http  2. 硬编码地址 (防止平台注入变量失败)
TARGET_URL=${E_http:-"https://foreign-vyky-zv201413-df1d4c4d.koyeb.app"}

echo "💓 Keepalive Daemon Started. Target: $TARGET_URL"

while true; do
    # 随机休眠 120-300 秒，防止请求过于规律
    sleep $((RANDOM % 180 + 120))
    
    # 执行保活访问
    status=$(curl -o /dev/null -s -w "%{http_code}" "$TARGET_URL/status")
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Status: $status" >> /tmp/keepalive.log
    
    # 自动清理日志，防止撑爆磁盘
    if [ $(wc -l < /tmp/keepalive.log) -gt 50 ]; then sed -i '1,25d' /tmp/keepalive.log; fi
done
EOF
RUN chmod +x /usr/local/bin/keepalive.sh

# 5. SSH 环境预处理
RUN mkdir -p /run/sshd && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 6. 配置文件与脚本处理
RUN mkdir -p /usr/local/etc
COPY supervisord.conf /usr/local/etc/supervisord.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN rm -f /etc/supervisor/supervisord.conf

USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
