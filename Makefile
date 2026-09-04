# Theos Makefile - 用于 GitHub Actions 编译
# 本地 Windows 编译请使用 build/build_dylib.sh

export TARGET := iphone:clang:16.5:14.0
# rootful 构建，RootHidePatcher 在设备上转换为 rootless
#THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FileShareTweak
FileShareTweak_FILES = Tweak.xm
FileShareTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
FileShareTweak_PRIVATE_FRAMEWORKS = MobileCoreServices UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"