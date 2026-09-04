//
// FSTSettingsController.m
// FileShareTweak 设置面板控制器（最小实现）
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <unistd.h>

// PSListController 是 Settings 进程运行时已有的私有类；
// 这里只做前向声明，继承关系在运行时由 runtime 解析。
@interface PSListController : NSObject
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface FSTSettingsController : PSListController
- (void)respring;
@end

@implementation FSTSettingsController

// PSListController 默认会根据 Root.plist 自动加载；
// 这里保留 respring 动作，供 Root.plist 里的 PSButtonCell 调用。
- (void)respring {
    // 优先使用 sbreload；不存在则直接杀掉 SpringBoard 注销。
    const char *sb = "/var/jb/usr/bin/sbreload";
    if (access(sb, X_OK) == 0) {
        execl(sb, sb, (char *)NULL);
    }
    execl("/var/jb/usr/bin/killall", "killall", "-9", "SpringBoard", (char *)NULL);
}

@end
