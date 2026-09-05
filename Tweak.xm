#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/*
 * FileShareTweak - 诊断版 v1.0.10
 * 功能逻辑与 1.0.7 一致，额外在关键位置写诊断日志到：
 *   /var/jb/tmp/fileshare_diag.log   （fallback: NSTemporaryDirectory()）
 * 用途：确认 dylib 是否加载进 Filza、点文件时到底走了哪个 API / 哪个 Filza 内部类。
 */

static NSString *kFSPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist";

// ---- 诊断日志 ----
static void FSLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *ts = [NSDate date].description;
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, s];
    const char *c = line.UTF8String;
    FILE *f = fopen("/var/jb/tmp/fileshare_diag.log", "a");
    if (!f) {
        NSString *fb = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fileshare_diag.log"];
        f = fopen(fb.UTF8String, "a");
    }
    if (f) { fputs(c, f); fflush(f); fclose(f); }
    NSLog(@"[FSDiag] %@", s);
}

static BOOL getBoolPref(NSString *key, BOOL defaultValue) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kFSPrefsPath];
    if (dict && dict[key]) return [dict[key] boolValue];
    return defaultValue;
}

static BOOL openFileWithApp(NSURL *fileURL, NSString *bundleID) {
    Class cls = objc_getClass("LSApplicationWorkspace");
    if (!cls) { FSLog(@"openFile: LSApplicationWorkspace class NOT found"); return NO; }
    id ws = [cls performSelector:@selector(defaultWorkspace)];
    if (!ws) { FSLog(@"openFile: defaultWorkspace nil"); return NO; }

    SEL sel1 = NSSelectorFromString(@"openApplicationWithBundleIdentifier:URL:");
    if ([ws respondsToSelector:sel1]) {
        NSMethodSignature *sig = [ws methodSignatureForSelector:sel1];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:ws]; [inv setSelector:sel1];
        [inv setArgument:&bundleID atIndex:2];
        [inv setArgument:&fileURL atIndex:3];
        [inv invoke];
        BOOL ret = NO; [inv getReturnValue:&ret];
        FSLog(@"openFile: method1(%@) -> %@", bundleID, ret?@"YES":@"NO");
        if (ret) return YES;
    }

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
        FSLog(@"openFile: method2(%@) -> %@", bundleID, ret?@"YES":@"NO");
        if (ret) return YES;
    }
    return NO;
}

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

// 诊断弹窗：直接把命中的信息显示出来，省去读日志文件
static void presentDiag(NSString *method, NSURL *url, NSString *ext, NSArray *targets, BOOL prot) {
    UIViewController *top = topViewController();
    if (!top) return;
    NSArray *syms = [NSThread callStackSymbols];
    if (syms.count > 14) syms = [syms subarrayWithRange:NSMakeRange(0, 14)];
    NSString *msg = [NSString stringWithFormat:
        @"method=%@\next=%@\nurl=%@\nprotected=%d\ntargets=%@\n\nstack(前14):\n%@",
        method, ext, url, prot, targets, [syms componentsJoinedByString:@"\n"]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"[FSDiag] 命中"
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    if (a.popoverPresentationController) {
        a.popoverPresentationController.sourceView = top.view;
        a.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width/2,
                                                                top.view.bounds.size.height/2, 1, 1);
    }
    [top presentViewController:a animated:YES completion:nil];
}

// method: 调用来源，便于在日志里区分是哪种弹法
static BOOL handleDocController(id self, NSString *method) {
    if (isProtectedProcess()) return NO;
    NSURL *fileURL = [self URL];
    if (!fileURL) { FSLog(@"docController(%@): URL nil", method); return NO; }
    NSString *ext = [[fileURL path] pathExtension].lowercaseString;
    NSArray *targets = targetsForExt(ext);
    FSLog(@"docController(%@) url=%@ ext=%@ targets=%@ prefOn=%d",
          method, fileURL, ext, targets, prefOnForExt(ext));
    FSLog(@"stack:\n%@", [NSThread callStackSymbols]);
    presentDiag(method, fileURL, ext, targets, NO);
    if (!targets.count || !prefOnForExt(ext)) return NO;

    for (NSString *bid in targets) {
        if (openFileWithApp(fileURL, bid)) return YES;
    }
    presentChooser(fileURL, ext);
    return YES;
}

%hook UIDocumentInteractionController

- (instancetype)initWithURL:(NSURL *)url {
    FSLog(@"UIDIC initWithURL: %@", url);
    return %orig;
}

- (BOOL)presentOptionsMenuFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (handleDocController(self, @"presentOptionsMenuFromRect:")) return NO;
    return %orig;
}

- (BOOL)presentOpenInMenuFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (handleDocController(self, @"presentOpenInMenuFromRect:")) return NO;
    return %orig;
}

- (void)presentOptionsMenuFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (handleDocController(self, @"presentOptionsMenuFromBarButtonItem:")) return;
    %orig;
}

- (void)presentOpenInMenuFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (handleDocController(self, @"presentOpenInMenuFromBarButtonItem:")) return;
    %orig;
}

- (void)presentPreviewAnimated:(BOOL)animated {
    if (!isProtectedProcess()) {
        NSURL *fileURL = [self URL];
        NSString *ext = [[fileURL path] pathExtension].lowercaseString;
        NSArray *targets = targetsForExt(ext);
        FSLog(@"UIDIC presentPreviewAnimated: url=%@ ext=%@ targets=%@", fileURL, ext, targets);
        FSLog(@"stack:\n%@", [NSThread callStackSymbols]);
        presentDiag(@"presentPreviewAnimated:", fileURL, ext, targets, NO);
    }
    %orig;
}

%end

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
        FSLog(@"UIActivityVC init items=%@", items);
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

// 兜底：跟踪系统 openURL，看 Filza 是否绕过 doc controller 直接 openURL
%hook UIApplication
- (BOOL)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSString *scheme = url.scheme ?: @"";
    if ([scheme isEqualToString:@"file"]) {
        FSLog(@"UIApplication openURL(file): %@ (from %@)", url, bid);
        FSLog(@"stack:\n%@", [NSThread callStackSymbols]);
        NSString *ext = [[url path] pathExtension].lowercaseString;
        NSArray *targets = targetsForExt(ext);
        presentDiag(@"UIApplication.openURL:file", url, ext, targets, NO);
    }
    return %orig;
}
%end

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    FSLog(@"========== FileShareTweak v1.0.11 LOADED ==========");
    FSLog(@"pid=%d bundle=%@ protected=%d", getpid(), bid, isProtectedProcess());
    // 探测目标 App 是否安装
    Class cls = objc_getClass("LSApplicationWorkspace");
    if (cls) {
        id ws = [cls performSelector:@selector(defaultWorkspace)];
        for (NSString *t in @[@"wiki.qaq.slpmods.TrollFools",@"com.huami.TrollFools",@"wiki.qaq.TrollFools",@"org.coolstar.SileoStore",@"com.opa334.TrollStore"]) {
            BOOL inst = NO;
            if ([ws respondsToSelector:@selector(applicationIsInstalled:)]) {
                NSMethodSignature *sig = [ws methodSignatureForSelector:@selector(applicationIsInstalled:)];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:ws]; [inv setSelector:@selector(applicationIsInstalled:)];
                NSString *arg = t;
                [inv setArgument:&arg atIndex:2]; [inv invoke];
                [inv getReturnValue:&inst];
            }
            FSLog(@"probe %@ installed=%d", t, inst);
        }
    }
}
