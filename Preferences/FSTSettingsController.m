//
// FSTSettingsController.m
// FileShareTweak 设置面板控制器
//
#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
#include <unistd.h>

@interface FSTSettingsController : PSListController
- (void)respring;
@end

@implementation FSTSettingsController

// 关键修复：必须重写 specifiers 并显式从 Root.plist 加载。
// PSListController 默认不会自动读取 Root.plist，不写这个面板就是空白的。
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    // 优先使用 sbreload；不存在则直接杀掉 SpringBoard 注销。
    const char *sb = "/var/jb/usr/bin/sbreload";
    if (access(sb, X_OK) == 0) {
        execl(sb, sb, (char *)NULL);
    }
    execl("/var/jb/usr/bin/killall", "killall", "-9", "SpringBoard", (char *)NULL);
}

@end
