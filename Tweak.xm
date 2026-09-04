#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/*
 * FileShareTweak - 一键分享到目标应用
 * 功能：点击/分享 dylib → TrollFools、ipa/tipa → TrollStore、deb → Sileo
 * 偏好文件：/var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist
 *
 * v1.0.7：覆盖 UIDocumentInteractionController 全部 4 种弹法（Filza 走 OpenIn 路径），
 *         并在 UIActivityViewController（系统分享菜单）中注入 FileShare 动作，
 *         路由失败时弹出选择框兜底，保证用户一定能看到插件生效。
 */

static NSString *kFSPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist";

static BOOL getBoolPref(NSString *key, BOOL defaultValue) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kFSPrefsPath];
    if (dict && dict[key]) return [dict[key] boolValue];
    return defaultValue;
}

// 用 LSApplicationWorkspace 把文件路由到目标 App；尝试两种私有方法，任一成功即返回 YES
static BOOL openFileWithApp(NSURL *fileURL, NSString *bundleID) {
    Class cls = objc_getClass("LSApplicationWorkspace");
    if (!cls) return NO;
    id ws = [cls performSelector:@selector(defaultWorkspace)];
    if (!ws) return NO;

    // 方法 1：openApplicationWithBundleIdentifier:URL:
    SEL sel1 = NSSelectorFromString(@"openApplicationWithBundleIdentifier:URL:");
    if ([ws respondsToSelector:sel1]) {
        NSMethodSignature *sig = [ws methodSignatureForSelector:sel1];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:ws]; [inv setSelector:sel1];
        [inv setArgument:&bundleID atIndex:2];
        [inv setArgument:&fileURL atIndex:3];
        [inv invoke];
        BOOL ret = NO; [inv getReturnValue:&ret];
        if (ret) return YES;
    }

    // 方法 2：openURL:withApplication:isSensitive:options:error:
    SEL sel2 = NSSelectorFromString(@"openURL:withApplication:isSensitive:options:error:");
    if ([ws respondsToSelector:sel2]) {
        NSMethodSignature *sig = [ws methodSignatureForSelector:sel2];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:ws]; [inv setSelector:sel2];
        BOOL sensitive = NO;
        NSDictionary *options = @{};
        NSError *error = nil;
        [inv setArgument:&fileURL atIndex:2];
        [inv setArgument:&bundleID atIndex:3];
        [inv setArgument:&sensitive atIndex:4];
        [inv setArgument:&options atIndex:5];
        [inv setArgument:&error atIndex:6];
        [inv invoke];
        BOOL ret = NO; [inv getReturnValue:&ret];
        if (ret) return YES;
    }
    return NO;
}

// 受保护进程（绝不注入 / 绝不挂钩），避免包管理器崩溃或 deb->Sileo 死循环
static BOOL isProtectedProcess() {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid) return NO;
    NSArray *exact = @[
        @"com.apple.springboard",
        @"org.coolstar.SileoStore",
        @"xyz.willy.Zebra",
        @"wiki.qaq.saily",
        @"com.saurik.Cydia",
        @"com.apple.installer",
    ];
    NSString *low = [bid lowercaseString];
    for (NSString *b in exact) {
        if ([low isEqualToString:[b lowercaseString]]) return YES;
    }
    NSArray *subs = @[@"sileo", @"zebra", @"saily", @"cydia", @"installer"];
    for (NSString *s in subs) {
        if ([low containsString:s]) return YES;
    }
    return NO;
}

// 扩展名 -> 目标 App bundle 列表（按顺序尝试）
static NSArray *targetsForExt(NSString *ext) {
    if ([ext isEqualToString:@"dylib"])
        return @[@"wiki.qaq.slpmods.TrollFools", @"com.huami.TrollFools", @"wiki.qaq.TrollFools"];
    if ([ext isEqualToString:@"deb"])
        return @[@"org.coolstar.SileoStore"];
    if ([ext isEqualToString:@"ipa"] || [ext isEqualToString:@"tipa"])
        return @[@"com.opa334.TrollStore"];
    return nil;
}

static NSString *displayNameForBundle(NSString *bid) {
    NSDictionary *map = @{
        @"wiki.qaq.slpmods.TrollFools": @"TrollFools",
        @"com.huami.TrollFools": @"TrollFools",
        @"wiki.qaq.TrollFools": @"TrollFools",
        @"org.coolstar.SileoStore": @"Sileo",
        @"com.opa334.TrollStore": @"TrollStore",
    };
    return map[bid] ?: bid;
}

static BOOL prefOnForExt(NSString *ext) {
    if ([ext isEqualToString:@"dylib"]) return getBoolPref(@"dylib_enabled", YES);
    if ([ext isEqualToString:@"deb"])   return getBoolPref(@"deb_enabled", YES);
    if ([ext isEqualToString:@"ipa"] || [ext isEqualToString:@"tipa"]) return getBoolPref(@"ipa_enabled", YES);
    return NO;
}

static UIViewController *topViewController() {
    UIViewController *root = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { root = w.rootViewController; break; }
                }
            }
            if (root) break;
        }
    }
    if (!root) root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// 弹选择框兜底，保证用户能看到“插件生效”
static void presentChooser(NSURL *fileURL, NSString *ext) {
    NSArray *targets = targetsForExt(ext);
    if (!targets.count || !prefOnForExt(ext)) return;
    UIViewController *top = topViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"FileShareTweak"
                                                                  message:[fileURL lastPathComponent]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *bid in targets) {
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"用 %@", displayNameForBundle(bid)]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { openFileWithApp(fileURL, bid); }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = top.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width / 2,
                                                                    top.view.bounds.size.height / 2, 1, 1);
    }
    [top presentViewController:alert animated:YES completion:nil];
}

// 处理 UIDocumentInteractionController；返回 YES 表示已接管（抑制系统菜单）
static BOOL handleDocController(id self) {
    if (isProtectedProcess()) return NO;
    NSURL *fileURL = [self URL];
    if (!fileURL) return NO;
    NSString *ext = [[fileURL path] pathExtension].lowercaseString;
    NSArray *targets = targetsForExt(ext);
    if (!targets.count || !prefOnForExt(ext)) return NO;

    for (NSString *bid in targets) {
        if (openFileWithApp(fileURL, bid)) return YES;
    }
    // 自动路由失败 -> 弹选择框，让用户手动选
    presentChooser(fileURL, ext);
    return YES;
}

%hook UIDocumentInteractionController

- (BOOL)presentOptionsMenuFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (handleDocController(self)) return NO;
    return %orig;
}

- (BOOL)presentOpenInMenuFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (handleDocController(self)) return NO;
    return %orig;
}

- (void)presentOptionsMenuFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (handleDocController(self)) return;
    %orig;
}

- (void)presentOpenInMenuFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (handleDocController(self)) return;
    %orig;
}

%end

// 自定义分享动作：注入到系统分享菜单，点一下即路由到目标 App
@interface FSOpenActivity : UIActivity
@property (nonatomic, strong) NSURL *fsFileURL;
@end
@implementation FSOpenActivity
- (NSString *)activityType { return @"com.ps.filesharetweak.open"; }
- (NSString *)activityTitle { return @"FileShare 打开"; }
- (UIImage *)activityImage { return nil; }
- (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
- (BOOL)canPerformWithActivityItems:(NSArray *)items { return YES; }
- (void)prepareWithActivityItems:(NSArray *)items {}
- (void)performActivity {
    NSString *ext = [[self.fsFileURL path] pathExtension].lowercaseString;
    for (NSString *bid in targetsForExt(ext)) {
        if (openFileWithApp(self.fsFileURL, bid)) break;
    }
    [self activityDidFinish:YES];
}
@end

%hook UIActivityViewController

- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    if (!isProtectedProcess()) {
        NSMutableSet *seenExt = [NSMutableSet set];
        for (id item in items) {
            NSURL *u = nil;
            if ([item isKindOfClass:[NSURL class]]) u = item;
            else if ([item isKindOfClass:[NSString class]] && [item hasPrefix:@"file://"]) u = [NSURL URLWithString:item];
            if (!u) continue;
            NSString *ext = [[u path] pathExtension].lowercaseString;
            if (!targetsForExt(ext).count || !prefOnForExt(ext)) continue;
            if ([seenExt containsObject:ext]) continue;
            [seenExt addObject:ext];
            FSOpenActivity *act = [[FSOpenActivity alloc] init];
            act.fsFileURL = u;
            NSMutableArray *newActs = activities ? [activities mutableCopy] : [NSMutableArray array];
            [newActs addObject:act];
            activities = newActs;
        }
    }
    return %orig(items, activities);
}

%end

%ctor {
    NSLog(@"[FileShareTweak] loaded v1.0.7, prefs at %@", kFSPrefsPath);
}
