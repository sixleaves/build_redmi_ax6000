#!/bin/bash
# 用法：./patch_mycode.sh /path/to/openwrt /path/to/your/scripts

set -e

# 1. 参数检查
if [ $# -lt 2 ]; then
  echo "用法: $0 /path/to/openwrt /path/to/your/scripts"
  exit 1
fi

OPENWRT_PATH="$1"
SCRIPTS_PATH="$2"

PACKAGE_NAME="custom-scripts"
PACKAGE_DIR="$OPENWRT_PATH/package/$PACKAGE_NAME"

# 2. 预检
if [ ! -d "$OPENWRT_PATH" ]; then
  echo "错误: OpenWrt路径不存在: $OPENWRT_PATH"
  exit 1
fi

if [ ! -d "$SCRIPTS_PATH" ]; then
  echo "错误: 脚本文件夹不存在: $SCRIPTS_PATH"
  exit 1
fi

# 创建包的基础目录
mkdir -p "$PACKAGE_DIR/files/etc/init.d"
mkdir -p "$PACKAGE_DIR/files/usr/bin"

echo "正在处理自定义脚本..."

# 3. 定义文件映射 (在这里填入你还需要的文件)
# 格式：["你的脚本文件名"]="安装到固件的目标路径(不含files)"
declare -A file_mapping

# --- 示例：如果你还有其他脚本，请取消注释并修改下方 ---
# file_mapping["my_firewall_rule"]="/etc/init.d/"
# file_mapping["my_tool.sh"]="/usr/bin/"

# 如果你现在什么脚本都没有，只想生成一个空包占位，保持上面为空即可。
# 但如果没有文件，生成的包可能没啥意义，请确保 SCRIPTS_PATH 下至少有一个你想用的文件并在上方注册。

declare -a init_scripts

# 4. 复制文件并处理权限
for script in "${!file_mapping[@]}"; do
    source_file="$SCRIPTS_PATH/$script"
    target_subdir="${file_mapping[$script]}"
    target_dir="$PACKAGE_DIR/files$target_subdir"
    
    if [ -f "$source_file" ]; then
        cp "$source_file" "$target_dir"
        echo "已复制: $script -> $target_subdir"
        
        # 处理 init 脚本逻辑
        if [[ "$target_subdir" == "/etc/init.d/" ]]; then
            chmod +x "$target_dir/$script"
            init_scripts+=("$script")
        elif [[ "$target_subdir" == "/usr/bin/" ]]; then
            chmod +x "$target_dir/$script"
        else
            chmod 644 "$target_dir/$script"
        fi
    else
        echo "提示: 源目录未找到文件 $script，跳过。"
    fi
done

# 5. 生成 Makefile
echo "正在生成 Makefile..."

# 使用 4个空格作为缩进占位符，稍后替换为 Tab
cat > "$PACKAGE_DIR/Makefile" << EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=custom-scripts
PKG_VERSION:=1.0
PKG_RELEASE:=1

include \$(INCLUDE_DIR)/package.mk

define Package/custom-scripts
    SECTION:=utils
    CATEGORY:=Utilities
    TITLE:=My Custom Scripts Collection
    DEPENDS:=+busybox
endef

define Package/custom-scripts/description
    This package contains my personal custom scripts.
endef

define Build/Compile
    # 纯脚本包，无需编译
endef

define Package/custom-scripts/install
    \$(INSTALL_DIR) \$(1)/usr/bin
    \$(INSTALL_DIR) \$(1)/etc/init.d
    
    # 安装所有 /usr/bin 下的脚本 (如果有)
    [ -d ./files/usr/bin ] && [ "\$(ls -A ./files/usr/bin)" ] && \
        \$(INSTALL_BIN) ./files/usr/bin/* \$(1)/usr/bin/ || true

    # 安装所有 /etc/init.d 下的脚本 (如果有)
    [ -d ./files/etc/init.d ] && [ "\$(ls -A ./files/etc/init.d)" ] && \
        \$(INSTALL_BIN) ./files/etc/init.d/* \$(1)/etc/init.d/ || true
endef

EOF

# 6. 处理 postinst (自动启用 init 脚本)
if [ ${#init_scripts[@]} -gt 0 ]; then
    cat >> "$PACKAGE_DIR/Makefile" << EOF
define Package/custom-scripts/postinst
#!/bin/sh
[ -n "\$\${IPKG_INSTROOT}" ] || {
EOF

    for script in "${init_scripts[@]}"; do
        echo "    /etc/init.d/$script enable" >> "$PACKAGE_DIR/Makefile"
        echo "    /etc/init.d/$script start" >> "$PACKAGE_DIR/Makefile"
    done

    cat >> "$PACKAGE_DIR/Makefile" << EOF
}
exit 0
endef
EOF
fi

# 结尾
cat >> "$PACKAGE_DIR/Makefile" << EOF

\$(eval \$(call BuildPackage,custom-scripts))
EOF

# 7. 修复 Makefile 格式
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/^    /\t/g' "$PACKAGE_DIR/Makefile"
else
    sed -i 's/^    /\t/g' "$PACKAGE_DIR/Makefile"
fi

echo "=========================================="
echo "脚本包生成完毕: $PACKAGE_DIR"
echo "目前包内包含文件数: ${#file_mapping[@]}"
echo "请确保你在脚本的 'file_mapping' 部分填入了你需要的文件。"
echo "=========================================="
