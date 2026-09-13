#!/bin/sh

# 设置 /usr/bin/*.sh 的权限为 777
chmod 777 /usr/bin/*.sh 2>/dev/null

# 设置 /usr/bin/sing-box 的权限为 777
[ -f "/usr/bin/sing-box" ] && chmod 777 /usr/bin/sing-box

# 设置 nft_custom 的权限为 777
[ -f "/etc/init.d/nft_custom" ] && chmod +x /etc/init.d/nft_custom
# 启动 nft_custom
[ -f "/etc/init.d/nft_custom" ] && /etc/init.d/nft_custom enabled
[ -f "/etc/init.d/nft_custom" ] && /etc/init.d/nft_custom start
# 创建 /mnt/nas 目录（若不存在）
mkdir -p /mnt/nas
# 如果必须确保挂载成功，则需检查设备是否存在
if [ -b /dev/sda2 ]; then
    mount /dev/sda2 /mnt/nas
    echo "成功挂载设备到/mnt/nas"
else
    echo "警告：/dev/sda2 设备未找到，跳过挂载" >&2  # 将警告输出到标准错误
fi

# 确保脚本返回 0（成功）

# 创建 six 用户并精细授权 (安全修正版)
# 必须以 root 执行

set -e

USERNAME="six"
# 随机 12 位密码，可手动改。如果用户已存在，脚本会重置为此密码。
PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)"
SUDO_FILE="/etc/sudoers.d/${USERNAME}"
# 在此处替换为你自己的公钥！
# YOUR_PUBLIC_KEY="ssh-rsa AAAA..."
YOUR_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDSa4avN5ziuhWZH7Il2P59pVP1FlVH2nuhnoK470e7ubcWd/tqlqKwi9IdYvhM7aFboOTd8/uVfliX749I9eUrFPHk388fLPAb/UFle9Kxve/IE2Zb78Oh5RdXGBDEbofKxIXn6VUvA1lHbIHXlF/sVDaLKWR7ri4U6TzeprXdx71qkZ/24grZCB/p/xDxCCiYSc2jA3NL1Ssn+e0L0OMzJ4iSWwLIvdKXUclAYWCaX3OZy+R1acm43KAz7+KimWmOWkdGpYZmqCtyabAmET+xCToCQtHyELnNhmgJR+MH75S0HTqVKafT5JB4hxpKLMlO2Fvnwri3Ei59PIRICAQni53uT8cj5m2Jm3yMsoSc95Rzh3RGWlj0GQXijw5cje4TJi+qQk5aFF1VaBdQUXqxqEv+hGLytZ7Jjjk/ZfaVGNzOkRVgt06RujAew5N1DF99vY2E05QsGDVRnqtVAAhIHu8c/dFtGa3RCUeYQLMVRwfIgo0lbTuuBu2mg0Bi9XU8Ssr6CXfwhjLK3lSuT5rZeO2LURbCnltcOwDFxu39BFV0S2kTGV3CkaXDZDiSZgZYCEEwGNrUtCBljmsdcBirRDyG2gEITMfxbCi0BQi+SZWFs5+iC1k8ymwIUxl58GFSxd19STWQX8gxfCvPKikTe4G29kdryxaXa36Pau24mw== sweetcs@sweetcsdeMacBook-Pro.local"

echo ">>> 1. 安装必要软件包"
opkg update
opkg install shadow-useradd sudo luci-app-acl || true

echo ">>> 2. 创建或更新用户 ${USERNAME}"
if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd -m -s /bin/ash "${USERNAME}"
    echo "用户 ${USERNAME} 已创建。"
else
    echo "用户 ${USERNAME} 已存在，准备更新密码和配置。"
fi

# 统一设置/重置密码
echo -e "${PASSWORD}\n${PASSWORD}" | passwd "${USERNAME}"
echo "用户 ${USERNAME} 的密码已设置为：${PASSWORD}"


echo ">>> 3. 精细 sudo 授权"
mkdir -p /etc/sudoers.d
cat > "${SUDO_FILE}" <<EOF
# 允许 ${USERNAME} 重启网络、操作 sing-box/singctl（无需密码）
${USERNAME} ALL=(root) NOPASSWD: /etc/init.d/network restart
${USERNAME} ALL=(root) NOPASSWD: /usr/bin/sing-box
${USERNAME} ALL=(root) NOPASSWD: /usr/bin/singctl
EOF
chmod 440 "${SUDO_FILE}"
echo "Sudo 规则已写入 ${SUDO_FILE}"

echo ">>> 4. 配置 rpcd，授权 ${USERNAME} 登录 LuCI WebUI"
# 如果用户登录项不存在，则创建
if ! uci get rpcd."${USERNAME}" >/dev/null 2>&1; then
    uci add rpcd login
    uci rename rpcd.@login[-1]="${USERNAME}"
fi
uci set rpcd."${USERNAME}".username="${USERNAME}"
# 【重要】下面这行是关键修正：关联用户和ACL角色，实现权限控制
uci set rpcd."${USERNAME}".acls='["six"]'
# 【重要】下面这行已被删除，避免明文存储密码
# uci set rpcd."${USERNAME}".password="${PASSWORD}"
uci commit rpcd

# 创建 ACL 角色定义文件
cat > /usr/share/rpcd/acl.d/six.json <<'EOF'
{
  "six": {
    "description": "six full access",
    "read": {
      "ubus": { "*": ["*"] },
      "uci": ["*"]
    },
    "write": {
      "ubus": { "*": ["*"] },
      "uci": ["*"]
    }
  }
}
EOF
echo "LuCI ACL 规则已配置。"

# 清缓存 & 重载
rm -f /tmp/luci-indexcache
/etc/init.d/rpcd reload

echo ">>> 5. 配置 SSH 公钥认证"
# 确保 home 目录存在
mkdir -p "/home/${USERNAME}/.ssh"
# 写入公钥（覆盖模式，确保只有指定的公钥）
echo "${YOUR_PUBLIC_KEY}" > "/home/${USERNAME}/.ssh/authorized_keys"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
chown -R ${USERNAME}:${USERNAME} "/home/${USERNAME}"
echo "SSH 公钥已配置。"

echo ">>> 6. 完成！"
echo "----------------------------------------"
echo "用户名：${USERNAME}"
echo "初始密码：${PASSWORD}"
echo "请使用此密码登录 LuCI 或进行 sudo 操作。"
echo "建议首次登录 LuCI 后修改密码。"
echo "----------------------------------------"

exit 0
