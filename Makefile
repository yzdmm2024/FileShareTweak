# Theos Makefile - 用于 GitHub Actions 编译
# 本地 Windows 编译请使用 build/build_dylib.sh

export TARGET := iphone:clang:16.5:14.0
# rootless 构建：THEOS_PACKAGE_SCHEME=rootless 会把 layout/Library 安装到 /var/jb
THEOS_PACKAGE_SCHEME = rootless

# 构建偏好设置包子工程
SUBPROJECTS += Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FileShareTweak
FileShareTweak_FILES = Tweak.xm
FileShareTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
FileShareTweak_PRIVATE_FRAMEWORKS = MobileCoreServices UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

# 注意：绝不能在安装后脚本里 killall SpringBoard / sbreload，
# 否则会把正在执行 dpkg 事务的包管理器(Sileo/Zebra)一起杀掉，
# 导致 dpkg 状态库写一半留下 "interrupted"，下次打开包管理器就崩。
# 安装完成后请用户从越狱 App(Relaxin/Dopamine)手动 Respring 让插件生效。
