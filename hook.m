#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface TTUserModel : NSObject
- (void)setIsPro:(BOOL)isPro;
- (BOOL)isPro;
- (void)setProEndDate:(NSDate *)date;
- (NSDate *)proEndDate;
@end

@implementation NSObject (TTUserModelPatch)

- (void)patched_setIsPro:(BOOL)isPro {
    // Always set as true (or false based on the prompt "pro=false / proEndDate=1990" - the Frida script sets args[2] = proValue (which is 1), so passing true. Wait, the Frida log says "-> false" but proValue is 0x1, which is true! Let's set it to YES for pro).
    // Actually the prompt says "isPro] ... -> false" in the log but `ptr('0x1')` is YES in Objective-C. Let's force it to YES to simulate Pro, or NO to simulate non-pro. 
    // Wait, the frida script: `const proValue = ptr('0x1');` `args[2] = proValue;` `retval.replace(proValue);` - that means it forces it to `1` which is `YES`/`true`. The console log just hardcoded the string "false" by mistake in the original script!
    [self patched_setIsPro:YES]; 
}

- (BOOL)patched_isPro {
    return YES;
}

- (void)patched_setProEndDate:(NSDate *)date {
    NSDate *forcedDate = [NSDate dateWithTimeIntervalSince1970:4070908800]; // 2098 or so
    [self patched_setProEndDate:forcedDate];
}

- (NSDate *)patched_proEndDate {
    return [NSDate dateWithTimeIntervalSince1970:4070908800];
}

@end

__attribute__((constructor))
static void patch_init() {
    NSLog(@"[PatchZero] Hooking TTUserModel...");
    
    Class class = NSClassFromString(@"TTUserModel");
    if (!class) {
        NSLog(@"[PatchZero] TTUserModel class not found.");
        return;
    }

    SEL originalSelectors[] = {
        @selector(setIsPro:),
        @selector(isPro),
        @selector(setProEndDate:),
        @selector(proEndDate)
    };
    
    SEL patchedSelectors[] = {
        @selector(patched_setIsPro:),
        @selector(patched_isPro),
        @selector(patched_setProEndDate:),
        @selector(patched_proEndDate)
    };

    for (int i = 0; i < 4; i++) {
        Method originalMethod = class_getInstanceMethod(class, originalSelectors[i]);
        Method patchedMethod = class_getInstanceMethod([NSObject class], patchedSelectors[i]);
        
        if (originalMethod && patchedMethod) {
            method_exchangeImplementations(originalMethod, patchedMethod);
            NSLog(@"[PatchZero] Hooked %@", NSStringFromSelector(originalSelectors[i]));
        }
    }
    
    NSLog(@"[PatchZero] Hooking complete.");
}
