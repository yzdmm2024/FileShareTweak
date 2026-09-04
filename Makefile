# Theos Makefile - 用于 GitHub Actions 编译
# 本地 Windows 编译请使用 build/build_dylib.sh

export TARGET := iphone:clang:16.5:14.0
# rootless 构建：THEOS_PACKAGE_SCHEME=rootless 会把 layout/Library 安装到 /var/jb
THEOS_PACKAGE_SCHEME = rootless

# Relaxin/RootHide 环境要求 deb 的 Architecture 字段为 iphoneos-arm64e
THEOS_PACKAGE_ARCH = iphoneos-arm64e

include $(THEOS)/makefiles/common.mk

# ===== Tweak 主体 =====
TWEAK_NAME = FileShareTweak
FileShareTweak_FILES = Tweak.xm
FileShareTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
FileShareTweak_PRIVATE_FRAMEWORKS = MobileCoreServices UIKit

# ===== 偏好设置 Bundle（与 Tweak 打包到同一个 deb） =====
# 注意：Theos 的 SUBPROJECTS 会把子目录当作静态库链接进父工程，
#       不会把子工程的 bundle 产物单独 stage 进 deb。因此这里把
#       Preference Bundle 作为第二个 instance 直接在主 Makefile 构建。
BUNDLE_NAME = FileShareTweakSettings
FileShareTweakSettings_FILES = Preferences/FSTSettingsController.m
FileShareTweakSettings_INSTALL_PATH = /Library/PreferenceBundles
FileShareTweakSettings_FRAMEWORKS = UIKit Foundation
FileShareTweakSettings_PRIVATE_FRAMEWORKS = Preferences
FileShareTweakSettings_CFLAGS = -fobjc-arc
FileShareTweakSettings_RESOURCE_DIRS = Preferences/Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

# 注意：绝不能在安装后脚本里 killall SpringBoard / sbreload，
# 否则会把正在执行 dpkg 事务的包管理器(Sileo/Zebra)一起杀掉，
# 导致 dpkg 状态库写一半留下 "interrupted"，下次打开包管理器就崩。
# 安装完成后请用户从越狱 App(Relaxin/Dopamine)手动 Respring 让插件生效。
