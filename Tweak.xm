#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/*
 * FileShareTweak - 一键分享到目标应用
 * 功能：点击 dylib → TrollFools、ipa/tipa → TrollStore、deb → Sileo
 * 偏好文件：/var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist
 */

// ========== 偏好设置读取 ==========
static NSString *kFSPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist";

static BOOL getBoolPref(NSString *key, BOOL defaultValue) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kFSPrefsPath];
    if (dict) {
        id val = dict[key];
        if (val) return [val boolValue];
    }
    return defaultValue;
}

// ========== 使用 LSApplicationWorkspace 打开文件到指定 App ==========
static BOOL openFileWithApp(NSURL *fileURL, NSString *bundleID) {
    Class LSApplicationWorkspace = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace) {
        NSLog(@"[FileShareTweak] LSApplicationWorkspace not found");
        return NO;
    }

    id workspace = [LSApplicationWorkspace performSelector:@selector(defaultWorkspace)];
    if (!workspace) return NO;

    // 私有方法：
    // - (BOOL)openURL:(NSURL *)url withApplication:(NSString *)bundleID isSensitive:(BOOL)sensitive options:(NSDictionary *)options error:(NSError **)error
    SEL sel = NSSelectorFromString(@"openURL:withApplication:isSensitive:options:error:");
    if (![workspace respondsToSelector:sel]) {
        NSLog(@"[FileShareTweak] openURL:withApplication:isSensitive:options:error: not found");
        return NO;
    }

    NSMethodSignature *sig = [workspace methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:workspace];
    [inv setSelector:sel];

    BOOL sensitive = NO;
    NSDictionary *options = @{};
    NSError *error = nil;
    id strongURL = fileURL;
    id strongApp = bundleID;

    [inv setArgument:&strongURL atIndex:2];
    [inv setArgument:&strongApp atIndex:3];
    [inv setArgument:&sensitive atIndex:4];
    [inv setArgument:&options atIndex:5];
    [inv setArgument:&error atIndex:6];
    [inv invoke];

    BOOL ret = NO;
    [inv getReturnValue:&ret];
    return ret;
}

// ========== Hook UIDocumentInteractionController ==========
%hook UIDocumentInteractionController

- (BOOL)presentOptionsMenuFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    NSURL *fileURL = [self URL];
    if (!fileURL) return %orig;

    NSString *ext = [[fileURL path] pathExtension].lowercaseString;
    NSLog(@"[FileShareTweak] file ext: %@, path: %@", ext, [fileURL path]);

    // dylib → TrollFools
    if ([ext isEqualToString:@"dylib"] && getBoolPref(@"dylib_enabled", YES)) {
        NSArray *trollFools = @[@"wiki.qaq.slpmods.TrollFools", @"com.huami.TrollFools", @"wiki.qaq.TrollFools"];
        for (NSString *bid in trollFools) {
            if (openFileWithApp(fileURL, bid)) {
                NSLog(@"[FileShareTweak] dylib opened with %@", bid);
                return NO;
            }
        }
        // 降级
        [[UIApplication sharedApplication] openURL:fileURL options:@{} completionHandler:nil];
        return NO;
    }

    // deb → Sileo
    if ([ext isEqualToString:@"deb"] && getBoolPref(@"deb_enabled", YES)) {
        if (openFileWithApp(fileURL, @"org.coolstar.SileoStore")) {
            NSLog(@"[FileShareTweak] deb opened with Sileo");
            return NO;
        }
        return NO;
    }

    // ipa/tipa → TrollStore
    if (([ext isEqualToString:@"ipa"] || [ext isEqualToString:@"tipa"]) && getBoolPref(@"ipa_enabled", YES)) {
        if (openFileWithApp(fileURL, @"com.opa334.TrollStore")) {
            NSLog(@"[FileShareTweak] ipa/tipa opened with TrollStore");
            return NO;
        }
        return NO;
    }

    return %orig;
}

%end

// ========== 初始化 ==========
%ctor {
    NSLog(@"[FileShareTweak] loaded, prefs at %@", kFSPrefsPath);
}