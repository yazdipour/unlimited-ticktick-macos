#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#import <strings.h>

// PatchZero — final configuration (proven combo):
//   1. container redirect (writable Group Container for ad-hoc signing)
//   2. JSON wire patch (isPro/premium fields on the profile response)
//   3. surgical sqlite read interpose (premium from the LOCAL GRDB store)
//   4. piracy alert suppression (41 localized titles, answered with Stop)
//   5. full tamper-check guard layer transplanted from the proven 7371eae
//      build: window snapshot, menu protection + item re-enable, activation
//      policy pin, NSApp unhide, minimize guard, orderOut same-turn restore,
//      termination block, Cmd+Q safety valve.

// ── Piracy alert detection ───────────────────────────────────────────────────

static NSString *const kPatchZeroPiracyTitles[] = {
    @"Anwendung nicht lizenziert.",
    @"Aplicació no llicenciada.",
    @"Aplicación no autorizada",
    @"Aplicativo não licenciado",
    @"Aplicația nu este licențiată.",
    @"Aplikace není licencována.",
    @"Aplikacija ni licencirana.",
    @"Aplikacija nije licencirana.",
    @"Aplikasi Tidak Berlisensi.",
    @"Aplikasi Tidak Dilisensikan",
    @"Aplikácia nie je licencovaná.",
    @"Application Not Licensed",
    @"Application non licence",
    @"Applicazione non autorizzata.",
    @"Applikasjon ikke lisensiert",
    @"Applikationen er ikke licenseret.",
    @"Applikationen är inte licensierad.",
    @"Az alkalmazás nincs engedélyezve.",
    @"Ostrzeżenie o nielegalnej kopii aplikacji",
    @"Programa neleisti.",
    @"Programma nav licencēta.",
    @"Rhybudd Dros Fersiwn Anghyfreithlon",
    @"Sovellusta ei ole lisensoitu",
    @"Toepassing niet gelicentieerd",
    @"Uygulama Lisanslı Değil.",
    @"Προειδοποίηση για παραβίαση πνευματικών δικαιωμάτων",
    @"Попередження про порушення авторських прав.",
    @"Праграма не ліцэнзавана",
    @"Приложение не лицензировано",
    @"Приложението не е лицензирано.",
    @"אזהרת פרצות זכויות יוצרים",
    @"برنامہ لائسنس نہیں ہے۔",
    @"تحذير القرصنة",
    @"هشدار قانونی نسخه‌ی غیرمجاز",
    @"பிரதியேக உரிமை இல்லாத பயன்பாடு",
    @"แจ้งเตือนการละเมิดลิขสิทธิ์",
    @"Ứng dụng không được cấp phép",
    @"ライセンスされていないアプリケーション",
    @"盗版警告",
    @"盜版警告",
    @"해적판을 경고",
    nil,
};

static BOOL patchzero_alert_is_piracy_warning(NSAlert *alert) {
    NSString *title = alert.messageText ?: @"";
    for (NSUInteger i = 0; kPatchZeroPiracyTitles[i] != nil; i++) {
        if ([title isEqualToString:kPatchZeroPiracyTitles[i]]) {
            return YES;
        }
    }
    NSString *info = alert.informativeText ?: @"";
    NSString *lowerTitle = title.lowercaseString;
    NSString *lowerInfo = info.lowercaseString;
    BOOL mentionsTickTickInInfo = [lowerInfo containsString:@"ticktick"];
    BOOL piracyKeyword = [lowerInfo containsString:@"pirat"]
        || [lowerInfo containsString:@"пират"]
        || [lowerInfo containsString:@"raubkopiert"]
        || [lowerInfo containsString:@"bajak"]
        || [lowerInfo containsString:@"illegal"]
        || [lowerInfo containsString:@"nelegal"]
        || [lowerInfo containsString:@"盗版"]
        || [lowerInfo containsString:@"海賊"]
        || [lowerInfo containsString:@"해적"]
        || [lowerTitle containsString:@"licens"]
        || [lowerTitle containsString:@"лицензирован"];
    return mentionsTickTickInInfo && piracyKeyword;
}

// ── Termination block (armed briefly after each suppression) ────────────────

static volatile BOOL patchzero_block_termination = NO;

static void patchzero_arm_termination_block(void) {
    patchzero_block_termination = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchzero_block_termination = NO;
    });
}

@implementation NSApplication (PatchZeroBlockForcedQuit)

- (void)patched_terminate:(id)sender {
    if (patchzero_block_termination) {
        NSLog(@"[PatchZero] Blocked an app termination request during the post-alert window.");
        return;
    }
    [self patched_terminate:sender];
}

@end

static BOOL patchzero_in_launch_window(void);
static volatile BOOL gPatchZeroQuitting = NO;

// TickTick hides the whole application after the first integrity-check answer.
// This is distinct from NSWindow orderOut and is the cause of the launch fold.
static volatile BOOL gPatchZeroBlockStartupHide = NO;

@implementation NSApplication (PatchZeroBlockStartupHide)

- (void)patched_hide:(id)sender {
    if (gPatchZeroBlockStartupHide && patchzero_in_launch_window() && !gPatchZeroQuitting) {
        NSLog(@"[PatchZero] Blocked automatic application hide during startup.");
        return;
    }
    [self patched_hide:sender];
}

@end

// ── Main menu protection ─────────────────────────────────────────────────────

static NSMenu *gPatchZeroProtectedMenu = nil;

@implementation NSApplication (PatchZeroProtectMainMenu)

- (void)patched_setMainMenu:(NSMenu *)menu {
    if (menu == nil || menu.numberOfItems == 0) {
        if (gPatchZeroProtectedMenu != nil && [self mainMenu] != gPatchZeroProtectedMenu) {
            NSLog(@"[PatchZero] Blocked clearing of main menu (tamper check), restoring.");
            [self patched_setMainMenu:gPatchZeroProtectedMenu];
        }
        return; // refuse to clear the menu
    }
    if (gPatchZeroProtectedMenu == nil) {
        gPatchZeroProtectedMenu = [menu retain];
    }
    [self patched_setMainMenu:menu];
}

@end

// Re-enable every menu item that has an action (recursively through submenus).
// The tamper check disables items via setEnabled:NO; called on each
// suppression so the menu bar comes back alive.
static void patchzero_enable_menu_items(NSMenu *menu) {
    if (menu == nil) {
        return;
    }
    for (NSMenuItem *item in [menu itemArray]) {
        if (item.hasSubmenu) {
            patchzero_enable_menu_items(item.submenu);
        }
        if (item.action != NULL) {
            item.enabled = YES;
        }
    }
}

// ── Activation policy pin ────────────────────────────────────────────────────

@implementation NSApplication (PatchZeroProtectActivationPolicy)

- (void)patched_setActivationPolicy:(NSApplicationActivationPolicy)policy {
    if (policy != NSApplicationActivationPolicyRegular) {
        NSLog(@"[PatchZero] Blocked setActivationPolicy:%ld (tamper check), keeping Regular.", (long)policy);
        policy = NSApplicationActivationPolicyRegular;
    }
    [self patched_setActivationPolicy:policy];
}

@end

// ── Window snapshot + reopen pass (transplanted from proven 7371eae) ────────

// Window number of the last suppressed piracy alert, kept so the reopen pass
// does not raise an empty NSAlert window over the app's real UI.
static NSInteger gPatchZeroSuppressedWindowNumber = 0;

// Rolling snapshot of window numbers that are actually visible and not
// miniaturized, refreshed every 0.5s. The reopen pass uses this to
// distinguish "windows the tamper check just hid" (show them again) from
// "windows the user closed/minimized on purpose" (leave them alone).
#define kPatchZeroMaxTrackedWindows 64
static NSInteger gPatchZeroTrackedWindowNumbers[kPatchZeroMaxTrackedWindows];
static int gPatchZeroTrackedWindowCount = 0;

static void patchzero_snapshot_visible_windows(void) {
    gPatchZeroTrackedWindowCount = 0;
    for (NSWindow *window in [NSApplication sharedApplication].windows) {
        if (!window.isVisible || window.isMiniaturized) {
            continue;
        }
        if (gPatchZeroTrackedWindowCount >= kPatchZeroMaxTrackedWindows) {
            break;
        }
        gPatchZeroTrackedWindowNumbers[gPatchZeroTrackedWindowCount++] = window.windowNumber;
    }
}

static BOOL patchzero_is_window_number_tracked(NSInteger windowNumber) {
    for (int i = 0; i < gPatchZeroTrackedWindowCount; i++) {
        if (gPatchZeroTrackedWindowNumbers[i] == windowNumber) {
            return YES;
        }
    }
    return NO;
}

// NOTE: the "universal launch-fold sweep" was REMOVED. It could not tell the
// tamper fold from the user's own closes inside the launch window — it kept
// re-opening Settings/Premium panels the user had just closed and fought the
// app in a visible flicker loop (20:52 log). Window handling is back to the
// proven 79a21ce behavior: only the orderOut hook below, main window only,
// only when the app is completely windowless.

// ── Windowless-app restore ───────────────────────────────────────────────────
// The tamper check can orderOut the main window at launch, leaving the app
// windowless. Restore only in that exact case, only in the first 20s of
// process life, and never after Cmd+Q. No other window is ever touched, so
// user opens/closes (Settings, Premium panels, Dock, yellow button) are
// fully native.

static NSDate *gPatchZeroLaunchTime = nil;
// Set when the user pressed Cmd+Q: all window-recovery paths must stand down,
// otherwise the orderOut restore pulls the window back on screen WHILE the app
// is quitting (seen in the 20:36 log: "Cmd+Q" followed by "restoring main window").

static volatile BOOL gPatchZeroBlockStartupOrderOut = NO;

static BOOL patchzero_in_launch_window(void) {
    return gPatchZeroLaunchTime != nil
        && [[NSDate date] timeIntervalSinceDate:gPatchZeroLaunchTime] < 20.0;
}

static void patchzero_arm_startup_orderout_guard(void) {
    gPatchZeroBlockStartupOrderOut = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gPatchZeroBlockStartupOrderOut = NO;
    });
}
@implementation NSWindow (PatchZeroRestoreAfterTamperHide)

- (void)patched_orderOut:(id)sender {
    BOOL isStartupWindow = gPatchZeroBlockStartupOrderOut && patchzero_in_launch_window()
        && !gPatchZeroQuitting && [self windowNumber] != gPatchZeroSuppressedWindowNumber
        && ![self isKindOfClass:[NSPanel class]] && (self.styleMask & NSWindowStyleMaskTitled);
    [self patched_orderOut:sender];
    if (isStartupWindow) {
        // Let AppKit complete the transaction before restoring the window.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!gPatchZeroQuitting && patchzero_in_launch_window() && !self.isMiniaturized) {
                NSLog(@"[PatchZero] Restoring startup window and focus after orderOut.");
                [self orderFront:nil];
                [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
                [self makeKeyWindow];
            }
        });
        return;
    }
    BOOL wasArmed = patchzero_in_launch_window() && !gPatchZeroQuitting
        && self == [[NSApplication sharedApplication] mainWindow];
    if (!wasArmed) {
        return;
    }
    // Restore ONLY if the app is now completely windowless — that is the
    // tamper-check fold. Legit UI flows (section switches, redraws) also
    // orderOut windows transiently while other windows stay visible; forcing
    // those back desynced the UI and blanked the task list.
    BOOL anyVisible = NO;
    for (NSWindow *w in [NSApplication sharedApplication].windows) {
        if (w.isVisible && !w.isMiniaturized) {
            anyVisible = YES;
            break;
        }
    }
    if (!anyVisible) {
        NSLog(@"[PatchZero] Tamper check left app windowless; restoring main window %ld same turn.", (long)[self windowNumber]);
        [self orderFront:nil];
        if ([[NSApplication sharedApplication] isActive]) {
            [self makeKeyWindow];
        }
    }
}

@end

static void patchzero_install_minimize_guard(void) {
    // Intentionally empty: launch-phase DidMiniaturize recovery was removed
    // together with the sweep — both fought the user's own window operations
    // (re-opened closed Settings/Premium panels, caused flicker). Proven
    // 79a21ce behavior restored: only the orderOut windowless-app guard.
    NSLog(@"[PatchZero] Window guards: orderOut windowless-restore only (no minimize interception).");
}

// ── Alert suppression ───────────────────────────────────────────────────────

@interface NSAlert (PatchZeroWindowAccess)
- (NSWindow *)window;
@end

// TickTick's first integrity-check response can miniaturize the main window.
// Recover only that startup transition, once; do not intercept normal Dock
// activation or user-initiated minimize after the app is usable.
static volatile BOOL gPatchZeroStartupWindowRecoveryScheduled = NO;

static void patchzero_restore_startup_window(void) {
    if (gPatchZeroQuitting || !patchzero_in_launch_window()
        || gPatchZeroStartupWindowRecoveryScheduled) {
        return;
    }
    gPatchZeroStartupWindowRecoveryScheduled = YES;
    // The integrity check may hide the app asynchronously, after the first
    // Only cover the initial integrity-check transition. A longer timer
    // conflicts with later Dock hide/show actions and steals focus repeatedly.
    __block int attempts = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        if (gPatchZeroQuitting || !patchzero_in_launch_window() || ++attempts > 20) {
            [timer invalidate];
            return;
        }

        NSApplication *app = [NSApplication sharedApplication];
        if (app.isHidden) {
            NSLog(@"[PatchZero] Startup integrity check hid application; unhiding it.");
            [app unhideWithoutActivation];
        }

        NSWindow *target = app.mainWindow;
        if (!target) {
            for (NSWindow *window in app.windows) {
                if ([window isKindOfClass:[NSPanel class]] || window == [NSApp keyWindow]) {
                    continue;
                }
                if ((window.styleMask & NSWindowStyleMaskTitled) && window.frame.size.width > 200.0
                    && window.frame.size.height > 150.0) {
                    target = window;
                    break;
                }
            }
        }
        if (!target) {
            return;
        }
        if (target.isMiniaturized) {
            NSLog(@"[PatchZero] Startup integrity check miniaturized window; restoring it.");
            [target deminiaturize:nil];
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
            [target makeKeyWindow];
        } else if (!target.isVisible) {
            NSLog(@"[PatchZero] Startup integrity check hid window; restoring it with focus.");
            [target orderFront:nil];
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
            [target makeKeyWindow];
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

// TickTick re-runs the integrity check when the app is activated from the Dock.
// Returning FirstButtonReturn on every invocation makes its "Download TickTick"
// path run repeatedly and leaves the app in a modal loop, so Dock activation
// never reaches the normal hide/minimize handling. Accept the first alert once
// during process lifetime, then cancel repeats without triggering that path.
static volatile BOOL gPatchZeroPiracyAlertAnswered = NO;

static void patchzero_hide_suppressed_alert_window(NSAlert *alert) {
    NSWindow *alertWindow = nil;
    if ([alert respondsToSelector:@selector(window)]) {
        @try {
            alertWindow = [alert window];
        } @catch (NSException *exception) {
            alertWindow = nil;
        }
    }
    if (alertWindow) {
        [alertWindow orderOut:nil];
        gPatchZeroSuppressedWindowNumber = [alertWindow windowNumber];
    }
}

@implementation NSAlert (PatchZeroSuppressPiracyWarning)

- (NSModalResponse)patched_runModal {
    if (patchzero_alert_is_piracy_warning(self)) {
        BOOL firstAnswer = !gPatchZeroPiracyAlertAnswered;
        gPatchZeroPiracyAlertAnswered = YES;
        NSLog(@"[PatchZero] Suppressed piracy warning alert (runModal), answering %@.",
              firstAnswer ? @"first button" : @"cancel for repeat");
        patchzero_hide_suppressed_alert_window(self);
        if (firstAnswer) {
            // The first-button response is the only response accepted by the
            // app's startup handler. Do it once, not on every Dock activation.
            patchzero_arm_termination_block();
            patchzero_arm_startup_orderout_guard();
            patchzero_restore_startup_window();
            return NSAlertFirstButtonReturn;
        }
        return NSModalResponseCancel;
    }
    return [self patched_runModal];
}

- (void)patched_beginSheetModalForWindow:(NSWindow *)sheetWindow completionHandler:(void (^)(NSModalResponse returnCode))handler {
    if (patchzero_alert_is_piracy_warning(self)) {
        BOOL firstAnswer = !gPatchZeroPiracyAlertAnswered;
        gPatchZeroPiracyAlertAnswered = YES;
        NSLog(@"[PatchZero] Suppressed piracy warning alert (sheet), answering %@.",
              firstAnswer ? @"first button" : @"cancel for repeat");
        patchzero_hide_suppressed_alert_window(self);
        if (firstAnswer) {
            patchzero_arm_termination_block();
            patchzero_restore_startup_window();
        }
        if (handler) {
            handler(firstAnswer ? NSAlertFirstButtonReturn : NSModalResponseCancel);
        }
        return;
    }
    [self patched_beginSheetModalForWindow:sheetWindow completionHandler:handler];
}

@end

@implementation NSWorkspace (PatchZeroSuppressAppStoreLink)

- (BOOL)patched_openURL:(NSURL *)url {
    if ([url.host containsString:@"apps.apple.com"] || [url.host containsString:@"itunes.apple.com"]) {
        NSLog(@"[PatchZero] Suppressed opening App Store URL: %@", url);
        return YES;
    }
    return [self patched_openURL:url];
}

@end

static void patchzero_install_piracy_warning_suppression(void) {
    Class cls = [NSAlert class];
    SEL originalSelectors[] = {
        @selector(runModal),
        @selector(beginSheetModalForWindow:completionHandler:)
    };
    SEL patchedSelectors[] = {
        @selector(patched_runModal),
        @selector(patched_beginSheetModalForWindow:completionHandler:)
    };
    for (int i = 0; i < 2; i++) {
        Method originalMethod = class_getInstanceMethod(cls, originalSelectors[i]);
        Method patchedMethod = class_getInstanceMethod(cls, patchedSelectors[i]);
        if (originalMethod && patchedMethod) {
            method_exchangeImplementations(originalMethod, patchedMethod);
        }
    }

    Class workspaceCls = [NSWorkspace class];
    Method originalOpenURL = class_getInstanceMethod(workspaceCls, @selector(openURL:));
    Method patchedOpenURL = class_getInstanceMethod(workspaceCls, @selector(patched_openURL:));
    if (originalOpenURL && patchedOpenURL) {
        method_exchangeImplementations(originalOpenURL, patchedOpenURL);
    }

    Class appCls = [NSApplication class];
    Method originalHide = class_getInstanceMethod(appCls, @selector(hide:));
    Method patchedHide = class_getInstanceMethod(appCls, @selector(patched_hide:));
    if (originalHide && patchedHide) {
        method_exchangeImplementations(originalHide, patchedHide);
        gPatchZeroBlockStartupHide = YES;
    }
    Method originalTerminate = class_getInstanceMethod(appCls, @selector(terminate:));
    Method patchedTerminate = class_getInstanceMethod(appCls, @selector(patched_terminate:));
    if (originalTerminate && patchedTerminate) {
        method_exchangeImplementations(originalTerminate, patchedTerminate);
    }

    NSLog(@"[PatchZero] Hooked NSAlert to suppress the piracy warning.");
}

static void patchzero_install_menu_protection(void) {
    Class cls = [NSApplication class];
    Method origMainMenu = class_getInstanceMethod(cls, @selector(setMainMenu:));
    Method replMainMenu = class_getInstanceMethod(cls, @selector(patched_setMainMenu:));
    Method origPolicy = class_getInstanceMethod(cls, @selector(setActivationPolicy:));
    Method replPolicy = class_getInstanceMethod(cls, @selector(patched_setActivationPolicy:));
    if (origMainMenu && replMainMenu) {
        method_exchangeImplementations(origMainMenu, replMainMenu);
        if (gPatchZeroProtectedMenu == nil) {
            gPatchZeroProtectedMenu = [[NSApplication sharedApplication].mainMenu retain];
        }
        NSLog(@"[PatchZero] Hooked setMainMenu: (menu bar protection).");
    } else {
        NSLog(@"[PatchZero] WARNING: could not hook setMainMenu:.");
    }
    if (origPolicy && replPolicy) {
        method_exchangeImplementations(origPolicy, replPolicy);
        NSLog(@"[PatchZero] Hooked setActivationPolicy: (pinned to Regular).");
    } else {
        NSLog(@"[PatchZero] WARNING: could not hook setActivationPolicy:.");
    }
}

static void patchzero_install_window_guards(void) {
    Class cls = [NSWindow class];
    Method origOut = class_getInstanceMethod(cls, @selector(orderOut:));
    Method replOut = class_getInstanceMethod(cls, @selector(patched_orderOut:));
    if (origOut && replOut) {
        method_exchangeImplementations(origOut, replOut);
        NSLog(@"[PatchZero] Hooked NSWindow orderOut: (windowless-app restore).");
    } else {
        NSLog(@"[PatchZero] WARNING: could not hook NSWindow orderOut:.");
    }
    patchzero_install_minimize_guard();
}

// ── Cmd+Q safety valve ───────────────────────────────────────────────────────

// Match by KEYCODE (12 = kVK_ANSI_Q), not by charactersIgnoringModifiers:
// on a Cyrillic layout the Q key yields "й", so a literal @"q" comparison
// misses Cmd+Q every time. keyCode 12 is layout-independent.
static void patchzero_install_quit_safety_valve(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        BOOL isCommandQ = (event.modifierFlags & NSEventModifierFlagCommand)
            && (event.keyCode == 12);
        if (isCommandQ) {
            gPatchZeroQuitting = YES;
            NSLog(@"[PatchZero] Cmd+Q seen (keyCode 12); will force-quit in 1s if the app hasn't quit by itself.");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[PatchZero] App still alive 1s after Cmd+Q; forcing exit.");
                exit(0);
            });
        }
        return event;
    }];
}

// ── JSON patch ──────────────────────────────────────────────────────────────

static const double kPatchZeroForcedProEndDateSeconds = 4070908800.0; // ~2098

static id patchzero_patch_json_object(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        for (id key in dict) {
            result[key] = patchzero_patch_json_object(dict[key]);
        }

        // Upstream semantics (proven on 8.2.20 by the c0afc96 build: premium
        // worked AND tasks survived sync): only rewrite keys the server
        // actually sent. Injecting ABSENT keys (isPro/isPremium/
        // premiumPaymentType) made every profile poll look "changed", the
        // sync engine rebuilt local data, and the task list vanished after
        // the first sync. Premium is held by the sqlite read interpose
        // (ZTTUSER.ZISPRO) — that is the layer gating the UI on 8.2.20.
        for (NSString *proKey in @[@"isPro", @"isTeamPro", @"isActiveTeamUser"]) {
            if (result[proKey] != nil && ![result[proKey] isEqual:@YES]) {
                NSLog(@"[PatchZero] Patched JSON field %@: %@ -> true", proKey, result[proKey]);
                result[proKey] = @YES;
            }
        }

        for (NSString *dateKey in @[@"proEndDate", @"vipEndDate"]) {
            id original = result[dateKey];
            if ([original isKindOfClass:[NSString class]]) {
                NSLog(@"[PatchZero] Patched JSON field %@: %@ -> 2098-12-13", dateKey, original);
                result[dateKey] = @"2098-12-13T00:00:00.000+0000";
            } else if ([original isKindOfClass:[NSNumber class]]) {
                double magnitude = [original doubleValue];
                BOOL looksLikeMilliseconds = fabs(magnitude) > 1e11;
                NSLog(@"[PatchZero] Patched JSON field %@: %@ -> 2098-12-13", dateKey, original);
                result[dateKey] = looksLikeMilliseconds
                    ? @(kPatchZeroForcedProEndDateSeconds * 1000.0)
                    : @(kPatchZeroForcedProEndDateSeconds);
            }
        }

        return result;
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)obj;
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            [result addObject:patchzero_patch_json_object(item)];
        }
        return result;
    }

    return obj;
}

@implementation NSJSONSerialization (PatchZeroJSON)

+ (id)patched_JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError * _Nullable __autoreleasing *)error {
    id result = [self patched_JSONObjectWithData:data options:opt error:error];
    return patchzero_patch_json_object(result);
}

@end

static void patchzero_install_json_patch(void) {
    Class cls = [NSJSONSerialization class];
    Method orig = class_getClassMethod(cls, @selector(JSONObjectWithData:options:error:));
    Method repl = class_getClassMethod(cls, @selector(patched_JSONObjectWithData:options:error:));
    if (orig && repl) {
        method_exchangeImplementations(orig, repl);
        NSLog(@"[PatchZero] Hooked NSJSONSerialization JSONObjectWithData:options:error:");
    } else {
        NSLog(@"[PatchZero] WARNING: could not hook NSJSONSerialization.");
    }
}

// ── Surgical sqlite read interpose ──────────────────────────────────────────
//
// Gate on the OWNING TABLE, not just the column name: forcing pro-columns on
// a JOIN or a same-named column of another table corrupts row reads (task
// lists stopped rendering on the second launch, when data comes from the
// local store instead of the wire). sqlite3_column_table_name tells us which
// table a result column really comes from; we only force when it is the user
// table. The first forced hit also logs the statement SQL once, so any future
// mismatch is visible in the log instead of guessed.

static int patchzero_col_logged_sql = 0;

static inline void patchzero_log_stmt_once(const sqlite3_stmt *stmt, const char *colname) {
    if (patchzero_col_logged_sql >= 8) return;
    patchzero_col_logged_sql++;
    const char *sql = sqlite3_sql((sqlite3_stmt *)stmt);
    NSLog(@"[PatchZero] sqlite force: col=%s stmt=%.300s", colname, sql ? sql : "<null>");
}

// Returns 1 only if the column belongs to the user table AND its name matches.
static inline int patchzero_col_is_user_pro(const sqlite3_stmt *stmt, int col, const char *const *names, int count) {
    const char *table = sqlite3_column_table_name((sqlite3_stmt *)stmt, col);
    if (!table) return 0;
    if (strcasecmp(table, "ZTTUSER") != 0 && strcasecmp(table, "USER") != 0 && strcasecmp(table, "user") != 0) {
        return 0;
    }
    const char *name = sqlite3_column_name((sqlite3_stmt *)stmt, col);
    if (!name) return 0;
    for (int i = 0; i < count; i++) {
        if (strcasecmp(name, names[i]) == 0) {
            patchzero_log_stmt_once(stmt, name);
            return 1;
        }
    }
    return 0;
}

static const char *const kPatchZeroProBoolColumns[] = {
    "ZISPRO", "isPro", "ZISTEAMPRO", "isTeamPro", "ZISACTIVETEAMUSER", "isActiveTeamUser",
};
static const char *const kPatchZeroProDateColumns[] = {
    "ZPROENDDATE", "proEndDate", "ZVIPENDDATE", "vipEndDate",
};
static const double kPatchZeroForcedProEndReferenceSeconds = 3092601600.0; // ~2098 (Core Data ref epoch)

int patchzero_sqlite3_column_int(sqlite3_stmt *stmt, int col) {
    if (patchzero_col_is_user_pro(stmt, col, kPatchZeroProBoolColumns, 6)) {
        return 1;
    }
    return sqlite3_column_int(stmt, col);
}

sqlite3_int64 patchzero_sqlite3_column_int64(sqlite3_stmt *stmt, int col) {
    if (patchzero_col_is_user_pro(stmt, col, kPatchZeroProBoolColumns, 6)) {
        return 1;
    }
    return sqlite3_column_int64(stmt, col);
}

double patchzero_sqlite3_column_double(sqlite3_stmt *stmt, int col) {
    if (patchzero_col_is_user_pro(stmt, col, kPatchZeroProDateColumns, 4)) {
        return kPatchZeroForcedProEndReferenceSeconds;
    }
    return sqlite3_column_double(stmt, col);
}

// NOTE: sqlite3_column_type is deliberately NOT interposed. Forcing the
// declared type of same-named columns on JOIN/other-table reads corrupted
// row parsing (task lists stopped rendering), even with name-only matching;
// re-adding it table-gated was judged not worth the regression risk. A NULL
// ZPROENDDATE before the first sync is acceptable: the ZISPRO int reads
// gate the UI, and the JSON wire patch persists a 2098 date on the first
// successful profile sync.

typedef struct patchzero_interpose_s {
    const void *replacement;
    const void *original;
} patchzero_interpose_t;

__attribute__((used)) static const patchzero_interpose_t patchzero_interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)patchzero_sqlite3_column_int, (const void *)sqlite3_column_int },
    { (const void *)patchzero_sqlite3_column_int64, (const void *)sqlite3_column_int64 },
    { (const void *)patchzero_sqlite3_column_double, (const void *)sqlite3_column_double },
};

// ── Container redirect ──────────────────────────────────────────────────────

static NSString *patchzero_redirected_group_path(NSString *groupIdentifier) {
    NSString *base = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Application Support/TickTickPatched/GroupContainers"];
    return [base stringByAppendingPathComponent:groupIdentifier];
}

@implementation NSFileManager (PatchZeroContainerRedirect)

- (NSURL *)patched_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSString *path = patchzero_redirected_group_path(groupIdentifier);
    [self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

@end

static void patchzero_install_container_redirect(void) {
    Class fm = [NSFileManager class];
    Method orig = class_getInstanceMethod(fm, @selector(containerURLForSecurityApplicationGroupIdentifier:));
    Method repl = class_getInstanceMethod(fm, @selector(patched_containerURLForSecurityApplicationGroupIdentifier:));
    if (orig && repl) {
        method_exchangeImplementations(orig, repl);
        NSLog(@"[PatchZero] Redirected App Group container to a writable path.");
    } else {
        NSLog(@"[PatchZero] WARNING: could not install container redirect.");
    }
}

// ── Init ─────────────────────────────────────────────────────────────────────

__attribute__((constructor))
static void patch_init() {
    gPatchZeroLaunchTime = [NSDate date];
    NSLog(@"[PatchZero] Hooking...");
    patchzero_install_container_redirect();
    patchzero_install_json_patch();
    patchzero_install_piracy_warning_suppression();
    NSLog(@"[PatchZero] Installed surgical sqlite premium read interpose (isPro/isTeamPro/isActiveTeamUser + proEndDate).");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchzero_install_quit_safety_valve();
        patchzero_install_menu_protection();
        patchzero_install_window_guards();
        // Snapshot timer: keep the tracked-window list fresh so the reopen
        // pass knows which windows were legitimately on screen. Every 4th
        // tick (~2s) also re-enable menu items — the tamper check greys them
        // out periodically, not just at launch.
        __block int tickCount = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            patchzero_snapshot_visible_windows();
            if (++tickCount % 4 == 0) {
                patchzero_enable_menu_items([NSApplication sharedApplication].mainMenu);
            }
        }];
        NSLog(@"[PatchZero] Installed Cmd+Q safety valve, menu protection, window guards.");
    });
}