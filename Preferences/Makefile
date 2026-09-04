# FileShareTweak 偏好设置包 Makefile

TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = FileShareTweakSettings
FileShareTweakSettings_FILES = FSTSettingsController.m
FileShareTweakSettings_INSTALL_PATH = /Library/PreferenceBundles
FileShareTweakSettings_FRAMEWORKS = UIKit Foundation
FileShareTweakSettings_PRIVATE_FRAMEWORKS = Preferences
FileShareTweakSettings_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
