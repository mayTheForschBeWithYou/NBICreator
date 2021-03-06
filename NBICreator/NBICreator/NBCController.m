//
//  NBCController.m
//  NBICreator
//
//  Created by Erik Berglund.
//  Copyright (c) 2015 NBICreator. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Imports
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

// Main
#import "NBCConstants.h"
#import "NBCController.h"
#import "NBCLog.h"

// Apple
#import <Security/Authorization.h>
#import <ServiceManagement/ServiceManagement.h>

// Helper
#import "NBCHelper.h"
#import "NBCHelperAuthorization.h"
#import "NBCHelperConnection.h"
#import "NBCHelperProtocol.h"

// UI
#import "NBCSourceDropViewController.h"
#import "NBCPreferences.h"

// Other
#import "NBCDiskArbitrator.h"
#import "NBCDiskImageController.h"
#import "NBCSource.h"
#import "NBCUpdater.h"
#import "NBCWorkflowManager.h"
#import "NBCWorkflowManager.h"
#import "Reachability.h"

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Constants
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

// --------------------------------------------------------------
//  Enum corresponding to segmented control position
// --------------------------------------------------------------
enum { kSegmentedControlNetInstall = 0, kSegmentedControlDeployStudio, kSegmentedControlImagr, kSegmentedControlCasper, kSegmentedControlCustom };

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCController Interface
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

@interface NBCController () {
    Reachability *_internetReachableFoo;
} // NBCController

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCController Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCController

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Init / Dealloc
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (id)init {
    self = [super init];
    if (self) {

        // --------------------------------------------------------------
        //  Event monitor to catch Option Key application wide
        // --------------------------------------------------------------
        NSEvent * (^monitorHandler)(NSEvent *);
        monitorHandler = ^NSEvent *(NSEvent *theEvent) {
            if ([theEvent modifierFlags] & NSAlternateKeyMask) {
                if ([self->_buttonBuild isEnabled]) {
                    [self->_buttonBuild setTitle:@"Build..."];
                }

                if ([self->_currentSettingsController isKindOfClass:[NBCDeployStudioSettingsViewController class]]) {
                    if ([[self->_currentSettingsController buttonDownloadDeployStudio] isHidden]) {
                        [[self->_currentSettingsController buttonDownloadDeployStudio] setHidden:NO];
                    }
                    [[self->_currentSettingsController buttonDownloadDeployStudio] setTitle:@"Download..."];
                }
            } else {
                if ([[self->_buttonBuild title] isEqualToString:@"Build..."]) {
                    [self->_buttonBuild setTitle:@"Build"];
                }

                if ([self->_currentSettingsController isKindOfClass:[NBCDeployStudioSettingsViewController class]]) {
                    if ([self->_currentSettingsController deployStudioDownloadButtonHidden]) {
                        [[self->_currentSettingsController buttonDownloadDeployStudio] setHidden:YES];
                    } else {
                        [[self->_currentSettingsController buttonDownloadDeployStudio] setHidden:NO];
                    }

                    if ([[[self->_currentSettingsController buttonDownloadDeployStudio] title] isEqualToString:@"Download..."]) {
                        [[self->_currentSettingsController buttonDownloadDeployStudio] setTitle:@"Download"];
                    }
                }
            }

            return theEvent;
        };

        _keyEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSFlagsChangedMask handler:monitorHandler];
    }
    return self;
} // init

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NBCNotificationUpdateButtonBuild object:nil];
} // dealloc

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Initialization
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (AuthorizationRef)createEmptyAuthorizationRef:(NSError **)error {
    DDLogDebug(@"Creating empty authorization reference...");
    AuthorizationRef authRef;
    OSStatus status = 0;

    // --------------------------------------------------------------
    //  Connect to the authorization system and create an authorization reference.
    // --------------------------------------------------------------
    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authRef);

    if (status == errAuthorizationSuccess) {
        DDLogDebug(@"Creating empty authorization reference successful!");
        return authRef;
    } else {
        DDLogError(@"[ERROR] Creating empty authorization reference failed!");
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        DDLogError(@"[ERROR] %@", [*error localizedDescription]);
    }

    return nil;
} // createEmptyAuthorizationRef

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods NSApplicationDelegate
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
#pragma unused(notification)

    // --------------------------------------------------------------
    //  Add Notification Observers
    // --------------------------------------------------------------
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(updateButtonBuild:) name:NBCNotificationUpdateButtonBuild object:nil];

    // --------------------------------------------------------------
    //  Register user defaults
    // --------------------------------------------------------------
    NSError *error;
    NSURL *defaultSettingsPath = [[NSBundle mainBundle] URLForResource:@"Defaults" withExtension:@"plist"];
    if ([defaultSettingsPath checkResourceIsReachableAndReturnError:&error]) {
        NSDictionary *defaultSettingsDict = [NSDictionary dictionaryWithContentsOfURL:defaultSettingsPath];
        if ([defaultSettingsDict count] != 0) {
            [[NSUserDefaults standardUserDefaults] registerDefaults:defaultSettingsDict];
        }
    } else {
        // Use NSLog as CocoaLumberjack isn't available yet
        NSLog(@"%@", [error localizedDescription]);
    }

    // --------------------------------------------------------------
    //  Setup logging
    // --------------------------------------------------------------
    [NBCLog configureLoggingFor:kWorkflowSessionTypeGUI];

    // --------------------------------------------------------------
    //  Setup preference window so it can recieve notifications
    // --------------------------------------------------------------
    if (!_preferencesWindow) {
        _preferencesWindow = [[NBCPreferences alloc] initWithWindowNibName:@"NBCPreferences"];
    }

    // --------------------------------------------------------------
    //  Test connection to the internet
    // --------------------------------------------------------------
    [self testInternetConnection];

    // --------------------------------------------------------------
    //  Register disk notifications
    // --------------------------------------------------------------
    [NBCDiskArbitrator sharedArbitrator];

    // --------------------------------------------------------------
    //  Check that helper tool is updated
    // --------------------------------------------------------------
    [self checkHelperVersion];

    // --------------------------------------------------------------
    //  Connect main menu items
    // --------------------------------------------------------------
    [_menuItemWindowWorkflows setAction:@selector(menuItemWindowWorkflows:)];
    [_menuItemWindowWorkflows setTarget:[NBCWorkflowManager sharedManager]];

    // --------------------------------------------------------------
    //  Restore last selected NBI type in segmented control
    // --------------------------------------------------------------
    int netBootSelection = (int)[[[NSUserDefaults standardUserDefaults] objectForKey:NBCUserDefaultsNetBootSelection] integerValue];
    [_segmentedControlNBI selectSegmentWithTag:netBootSelection];
    [self selectSegmentedControl:netBootSelection];

    // --------------------------------------------------------------
    //  Display Main Window
    // --------------------------------------------------------------
    [_window makeKeyAndOrderFront:self];
} // applicationDidFinishLaunching

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)__unused sender {
    return YES;
} // applicationShouldTerminateAfterLastWindowClosed

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)__unused sender {
    // --------------------------------------------------------------
    //  Run some checks before terminating application
    // --------------------------------------------------------------
    [self checkUnsavedSettingsQuit];
    return NSTerminateLater;
} // applicationShouldTerminate

- (void)applicationWillTerminate:(NSNotification *)__unused notification {

    DDLogDebug(@"[DEBUG] %s", __PRETTY_FUNCTION__);

    // --------------------------------------------------------------
    //  Unmount all disks and disk images mounted by NBICreator
    // --------------------------------------------------------------
    NSSet *mountedDisks = [[[NBCDiskArbitrator sharedArbitrator] disks] copy];
    if ([mountedDisks count] != 0) {
        for (NBCDisk *disk in mountedDisks) {
            if ([disk isMountedByNBICreator] && [disk isMounted]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self->_textFieldProgress setStringValue:[NSString stringWithFormat:@"Unmounting disk: %@", [disk BSDName]]];
                });
                [disk unmountWithOptions:kDADiskUnmountOptionDefault];
                if ([[disk deviceModel] isEqualToString:NBCDiskDeviceModelDiskImage]) {
                    [NBCDiskImageController detachDiskImageDevice:[disk BSDName]];
                }
            }
        }

        [[NSApp mainWindow] endSheet:self->_windowProgress];
    }

    NBCHelperConnection *helperConnector = [[NBCHelperConnection alloc] init];
    [helperConnector connectToHelper];
    [[[helperConnector connection] remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
      DDLogError(@"[ERROR] %@", [proxyError localizedDescription]);
    }] quitHelper:^(BOOL __unused success){

    }];
} // applicationWillTerminate

- (void)showTerminateProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSApp mainWindow] beginSheet:self->_windowProgress completionHandler:nil];
    });
} // showTerminateProgress

- (void)applicationDidBecomeActive:(NSNotification *)__unused notification {
    NSDockTile *dockTile = [NSApp dockTile];
    [dockTile setBadgeLabel:@""];
    [dockTile display];
}

- (BOOL)application:(NSApplication *)__unused theApplication openFile:(NSString *)filename {

    DDLogInfo(@"Recieved file to open: %@", filename);

    __block NSError *error = nil;
    NSURL *fileURL = [NSURL fileURLWithPath:filename];

    // --------------------------------------------------------------
    //  Try to read settings from sent file
    // --------------------------------------------------------------
    NSDictionary *templateInfo = [NBCTemplatesController templateInfoFromTemplateAtURL:fileURL error:&error];
    if ([templateInfo count] != 0) {
        NSString *title = templateInfo[NBCSettingsTitleKey];
        DDLogDebug(@"[DEBUG] Template title: %@", title);

        NSString *type = templateInfo[NBCSettingsTypeKey];
        DDLogDebug(@"[DEBUG] Template type: %@", type);

        // --------------------------------------------------------------
        //  Check if template settings are an exact duplicate of an existing template
        // --------------------------------------------------------------
        if ([NBCTemplatesController templateIsDuplicate:fileURL]) {
            [NBCAlerts showAlertImportTemplateDuplicate:[NSString stringWithFormat:@"The template you are trying to import is identical to an already existing template:\n\nWorkflow:\t%@\nName:\t%@",
                                                                                   type, title]];
            return NO;
        }

        if ([type isEqualToString:NBCSettingsTypeNetInstall]) {
            [self->_segmentedControlNBI selectSegmentWithTag:kSegmentedControlNetInstall];
            [self selectSegmentedControl:kSegmentedControlNetInstall];
        } else if ([type isEqualToString:NBCSettingsTypeDeployStudio]) {
            [self->_segmentedControlNBI selectSegmentWithTag:kSegmentedControlDeployStudio];
            [self selectSegmentedControl:kSegmentedControlDeployStudio];
        } else if ([type isEqualToString:NBCSettingsTypeImagr]) {
            [self->_segmentedControlNBI selectSegmentWithTag:kSegmentedControlImagr];
            [self selectSegmentedControl:kSegmentedControlImagr];
        } else if ([type isEqualToString:NBCSettingsTypeCasper]) {
            [self->_segmentedControlNBI selectSegmentWithTag:kSegmentedControlCasper];
            [self selectSegmentedControl:kSegmentedControlCasper];
        } else {
            [NBCAlerts showAlertErrorWithTitle:@"Import Error" informativeText:@"Unknown template type."];
            return NO;
        }

        // --------------------------------------------------------------
        //  Check if template title already is used in an existing template
        // --------------------------------------------------------------
        if ([NBCTemplatesController templateNameAlreadyExist:fileURL]) {
            DDLogInfo(@"Template name: \"%@\" already exist!", title);
            if (self->_currentSettingsController) {
                [[_currentSettingsController templates] showSheetRenameImportTemplateWithName:title url:fileURL];
            } else {
                [NBCAlerts showAlertErrorWithTitle:@"Import Error" informativeText:@"Internal Error, settings controller not instantiated."];
            }
        } else {
            NSString *importTitle = [NSString stringWithFormat:@"Import %@ Template?", type];
            NSString *importMessage = [NSString stringWithFormat:@"Do you want to import the %@ template \"%@\"?", type, title];

            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:@"Import"];
            [alert addButtonWithTitle:NBCButtonTitleCancel];
            [alert setMessageText:importTitle];
            [alert setInformativeText:importMessage];
            [alert setAlertStyle:NSInformationalAlertStyle];
            [alert beginSheetModalForWindow:[(NBCController *)[[NSApplication sharedApplication] delegate] window]
                          completionHandler:^(NSInteger returnCode) {
                            if (returnCode == NSAlertFirstButtonReturn) {
                                if (self->_currentSettingsController) {
                                    if (![[self->_currentSettingsController templates] importTemplateFromURL:fileURL newName:nil error:&error]) {
                                        DDLogError(@"[ERROR] %@", [error localizedDescription]);
                                        [NBCAlerts showAlertErrorWithTitle:@"Import Error" informativeText:[error localizedDescription]];
                                    }
                                } else {
                                    [NBCAlerts showAlertErrorWithTitle:@"Import Error" informativeText:@"Internal Error, settings controller not instantiated."];
                                }
                            }
                          }];
        }
        return YES;
    } else {
        [NBCAlerts showAlertErrorWithTitle:@"Import Error" informativeText:[error localizedDescription]];
        return NO;
    }
} // application:openFile

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods NSWindowDelegate
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)windowDidBecomeKey:(NSNotification *)notification {
#pragma unused(notification)
    // I'm seeing strange behaviour when using this. Going to try and disable and run without for testing.
    //[[NBCWorkflowManager sharedManager] menuItemWindowWorkflows:self];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Application Termination Checks
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)checkUnsavedSettingsQuit {

    // --------------------------------------------------------------
    //  Alert user if there are unsaved settings before quitting
    // --------------------------------------------------------------
    BOOL currentSettingsUnsaved = NO;
    int settingsUnsaved = 0;
    NSMutableString *settingsChanged = [[NSMutableString alloc] initWithString:@""];
    if (_niSettingsViewController && [_niSettingsViewController haveSettingsChanged]) {
        [settingsChanged appendString:@"• NetInstall\n"];
        settingsUnsaved++;
        if ([_niSettingsViewController isEqualTo:_currentSettingsController]) {
            currentSettingsUnsaved = YES;
        }
    }

    if (_dsSettingsViewController && [_dsSettingsViewController haveSettingsChanged]) {
        [settingsChanged appendString:@"• DeployStudio\n"];
        settingsUnsaved++;
        if ([_dsSettingsViewController isEqualTo:_currentSettingsController]) {
            currentSettingsUnsaved = YES;
        }
    }

    if (_imagrSettingsViewController && [_imagrSettingsViewController haveSettingsChanged]) {
        if (![_imagrSettingsViewController isNBI]) {
            [settingsChanged appendString:@"• Imagr\n"];
            settingsUnsaved++;
            if ([_imagrSettingsViewController isEqualTo:_currentSettingsController]) {
                currentSettingsUnsaved = YES;
            }
        }
    }

    if (_casperSettingsViewController && [_casperSettingsViewController haveSettingsChanged]) {
        [settingsChanged appendString:@"• Casper\n"];
        settingsUnsaved++;
        if ([_casperSettingsViewController isEqualTo:_currentSettingsController]) {
            currentSettingsUnsaved = YES;
        }
    }

    if (settingsUnsaved == 1 && currentSettingsUnsaved) {
        if ([[_currentSettingsController selectedTemplate] isEqualToString:NBCMenuItemUntitled]) {
            NBCAlerts *alerts = [[NBCAlerts alloc] initWithDelegate:self];
            [alerts showAlertSettingsUnsavedQuitNoSave:@"You have unsaved settings.\n\nTo save your changes in a template, select Save As... from the template popup menu and choose a name."
                                             alertInfo:@{NBCAlertTagKey : NBCAlertTagSettingsUnsavedQuitNoSave}];
        } else {
            NBCAlerts *alerts = [[NBCAlerts alloc] initWithDelegate:self];
            [alerts showAlertSettingsUnsavedQuit:@"You have unsaved settings." alertInfo:@{NBCAlertTagKey : NBCAlertTagSettingsUnsavedQuit}];
        }
    } else if (0 < settingsUnsaved) {
        NBCAlerts *alerts = [[NBCAlerts alloc] initWithDelegate:self];
        [alerts showAlertSettingsUnsavedQuitNoSave:[NSString stringWithFormat:@"You have unsaved settings for the following workflows:\n\n%@", settingsChanged]
                                         alertInfo:@{NBCAlertTagKey : NBCAlertTagSettingsUnsavedQuitNoSave}];
    } else {
        [self checkWorkflowRunningQuit];
    }
} // checkUnsavedSettingsQuit

- (void)checkWorkflowRunningQuit {

    // --------------------------------------------------------------
    //  Alert user if there are any workflows currently running before quitting
    // --------------------------------------------------------------
    if ([[NBCWorkflowManager sharedManager] workflowRunning]) {
        NBCAlerts *alerts = [[NBCAlerts alloc] initWithDelegate:self];
        [alerts showAlertWorkflowRunningQuit:@"A workflow is still running. If you quit now, the current workflow will cancel and delete the NBI in creation."
                                   alertInfo:@{NBCAlertTagKey : NBCAlertTagWorkflowRunningQuit}];
    } else {
        [self terminateApp];
    }
} // checkWorkflowRunningQuit

- (void)terminateApp {

    DDLogDebug(@"[DEBUG] Terminating application...");

    // --------------------------------------------------------------
    //  Show termination progress after 2 seconds
    // --------------------------------------------------------------
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_progressIndicatorProgress startAnimation:self];
      [self performSelector:@selector(showTerminateProgress) withObject:self afterDelay:2.0];
      [self->_textFieldProgress setStringValue:@"Removing temporary items..."];
    });

    NSString *applicationTemporaryFolderPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NBCBundleIdentifier];
    DDLogDebug(@"[DEBUG] Application temporary folder path: %@", applicationTemporaryFolderPath);

    if ([applicationTemporaryFolderPath length] != 0) {
        NSURL *applicationTemporaryFolderURL = [NSURL fileURLWithPath:applicationTemporaryFolderPath];
        if ([applicationTemporaryFolderURL checkResourceIsReachableAndReturnError:nil]) {

            DDLogDebug(@"[DEBUG] Removing application temporary folder...");

            dispatch_queue_t taskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_async(taskQueue, ^{

              NBCHelperConnection *helperConnector = [[NBCHelperConnection alloc] init];
              [helperConnector connectToHelper];
              [[helperConnector connection] setExportedObject:self];
              [[helperConnector connection] setExportedInterface:[NSXPCInterface interfaceWithProtocol:@protocol(NBCWorkflowProgressDelegate)]];
              [[[helperConnector connection] remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
                DDLogError(@"[ERROR] %@", [proxyError localizedDescription]);
                dispatch_async(dispatch_get_main_queue(), ^{
                  [[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
                });
              }] removeItemsAtPaths:@[ [applicationTemporaryFolderURL path] ]
                           withReply:^(NSError *error, BOOL success) {
                             if (!success) {
                                 DDLogError(@"[ERROR] %@", [error localizedDescription]);
                             }
                             dispatch_async(dispatch_get_main_queue(), ^{
                               [[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
                             });
                           }];
            });
        } else {
            [[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
        }
    } else {
        [[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
    }
} // terminateApp

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods NBCAlertsDelegate
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)alertReturnCode:(NSInteger)returnCode alertInfo:(NSDictionary *)alertInfo {
    NSString *alertTag = alertInfo[NBCAlertTagKey];
    if ([alertTag isEqualToString:NBCAlertTagSettingsUnsavedQuit]) {
        if (returnCode == NSAlertFirstButtonReturn) { // Save and Quit
            NSString *selectedTemplate = [_currentSettingsController selectedTemplate];
            NSDictionary *templatesDict = [_currentSettingsController templatesDict];
            [_currentSettingsController saveUISettingsWithName:selectedTemplate atUrl:templatesDict[selectedTemplate]];
            [self checkWorkflowRunningQuit];
        } else if (returnCode == NSAlertSecondButtonReturn) { // Quit
            [self checkWorkflowRunningQuit];
        } else { // Cancel
            [NSApp replyToApplicationShouldTerminate:NO];
        }
    } else if ([alertTag isEqualToString:NBCAlertTagSettingsUnsavedQuitNoSave]) {
        if (returnCode == NSAlertSecondButtonReturn) { // Quit Anyway
            [self checkWorkflowRunningQuit];
        } else { // Cancel
            [NSApp replyToApplicationShouldTerminate:NO];
        }
    } else if ([alertTag isEqualToString:NBCAlertTagWorkflowRunningQuit]) {
        if (returnCode == NSAlertSecondButtonReturn) { // Quit Anyway

            /*//////////////////////////////////////////////////////////////////////////////
             /// NEED TO IMPLEMENT THIS TO QUIT ALL RUNNING AND QUEUED WORKFLOWS         ///
             //////////////////////////////////////////////////////////////////////////////*/
            DDLogWarn(@"[WARN] Canceling all workflows...");
            /* --------------------------------------------------------------------------- */

            [self terminateApp];
        } else { // Cancel
            [NSApp replyToApplicationShouldTerminate:NO];
        }
    }
} // alertReturnCode:alertInfo

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Notification Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateButtonBuild:(NSNotification *)notification {

    BOOL buttonState = [[notification userInfo][NBCNotificationUpdateButtonBuildUserInfoButtonState] boolValue];

    // --------------------------------------------------------------
    //  Only enable build button if connection to helper has been successful
    // --------------------------------------------------------------
    if (_helperAvailable == YES) {
        [_buttonBuild setEnabled:buttonState];
        if (!buttonState) {
            [_buttonBuild setTitle:@"Build"];
        }
    } else {
        [_buttonBuild setEnabled:NO];
        [_buttonBuild setTitle:@"Build"];
    }
} // updateButtonBuild

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Helper Tool
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (BOOL)installHelper:(NSError **)error {

    // -----------------------------------------------------------------------
    //  Create an Authorization Right for removing AND installing helper tool
    // -----------------------------------------------------------------------
    DDLogDebug(@"[DEBUG] Creating authorization right...");

    AuthorizationRef authRef = [self createEmptyAuthorizationRef:error];
    if (!authRef) {
        return NO;
    }

    AuthorizationItem authItems[2] = {{kSMRightBlessPrivilegedHelper, 0, NULL, 0}, {kSMRightModifySystemDaemons, 0, NULL, 0}};
    AuthorizationRights authRights = {2, authItems};
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;

    // --------------------------------------------------------------
    //  Try to obtain the right from authorization system (Ask User)
    // --------------------------------------------------------------
    DDLogDebug(@"[DEBUG] Asking authorization system to grant right...");

    OSStatus status = AuthorizationCopyRights(authRef, &authRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (status != errAuthorizationSuccess) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        DDLogError(@"[ERROR] %@", [*error localizedDescription]);
        return NO;
    } else {

        // --------------------------------------------------------------
        //  Try to remove helper from laucnhd and files from disk
        // --------------------------------------------------------------
        if (![self removeHelperWithLabel:NBCBundleIdentifierHelper authRef:authRef error:error]) {
            return NO;
        }

        // --------------------------------------------------------------
        //  Try to install helper tool
        // --------------------------------------------------------------
        return [self blessHelperWithLabel:NBCBundleIdentifierHelper authRef:authRef error:error];
    }
} // installHelper

- (BOOL)removeHelperWithLabel:(NSString *)label authRef:(AuthorizationRef)authRef error:(NSError **)error {

    DDLogInfo(@"Removing helper tool...");

    BOOL result = NO;
    CFErrorRef cfError;

    // --------------------------------------------------------------
    //  Unload helper tool using SMJobRemove
    // --------------------------------------------------------------
    DDLogDebug(@"[DEBUG] Running SMJobRemove..");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ///////////////////////////////////////////////////////////////////////////////
    /// THIS IS DEPRECATED AS OF 10.10                                          ///
    ///////////////////////////////////////////////////////////////////////////////
    result = (BOOL)SMJobRemove(kSMDomainSystemLaunchd, (__bridge CFStringRef)label, authRef, true, &cfError);
    /* ------------------------------------------------------------------------- */
    if (!result) {
        DDLogError(@"[ERROR] Could not remove helper tool!");
        DDLogError(@"[ERROR] SMJobRemove failed!");
        *error = CFBridgingRelease(cfError);
        DDLogError(@"[ERROR] %@", [*error localizedDescription]);
    } else {

        // --------------------------------------------------------------
        //  Remove helper tool files on disk
        // --------------------------------------------------------------
        NSDictionary *removeHelperFilesLaunchdJob = @{
            @"Label" : [NSString stringWithFormat:@"%@.remove", NBCBundleIdentifierHelper],
            @"ProgramArguments" : @[ @"/bin/rm", NBCFilePathHelperLaunchd, NBCFilePathHelperTool ],
            @"RunAtLoad" : @YES,
            @"LaunchOnlyOnce" : @YES
        };

        DDLogDebug(@"[DEBUG] Running SMJobSubmit..");
        ///////////////////////////////////////////////////////////////////////////////
        /// THIS IS DEPRECATED AS OF 10.10                                          ///
        ///////////////////////////////////////////////////////////////////////////////
        if ((result = (BOOL)SMJobSubmit(kSMDomainSystemLaunchd, (__bridge CFDictionaryRef)removeHelperFilesLaunchdJob, authRef, &cfError))) {
            /* ------------------------------------------------------------------------- */
            [NSThread sleepForTimeInterval:0.5];
        } else {
            DDLogError(@"[ERROR] Could not remove helper tool files on disk");
            DDLogError(@"[ERROR] SMJobSubmit failed!");
            *error = CFBridgingRelease(cfError);
            DDLogError(@"[ERROR] %@", [*error localizedDescription]);
        }

        DDLogDebug(@"[DEBUG] Running SMJobRemove..");
        ///////////////////////////////////////////////////////////////////////////////
        /// THIS IS DEPRECATED AS OF 10.10                                          ///
        ///////////////////////////////////////////////////////////////////////////////
        if (!(result = (BOOL)SMJobRemove(kSMDomainSystemLaunchd, (__bridge CFStringRef)removeHelperFilesLaunchdJob[@"Label"], authRef, true, &cfError))) {
            /* ------------------------------------------------------------------------- */
            DDLogError(@"[ERROR] Could not remove launchd job");
            DDLogError(@"[ERROR] SMJobRemove failed!");
            *error = CFBridgingRelease(cfError);
            DDLogError(@"[ERROR] %@", [*error localizedDescription]);
        }
    }
#pragma clang diagnostic pop
    return result;
} // removeHelperWithLabel:authRef:error

- (BOOL)blessHelperWithLabel:(NSString *)label authRef:(AuthorizationRef)authRef error:(NSError **)error {

    DDLogInfo(@"Installing helper tool...");

    BOOL result = NO;
    CFErrorRef cfError;

    // --------------------------------------------------------------
    //  Install helper tool using SMJobBless
    // --------------------------------------------------------------
    DDLogDebug(@"[DEBUG] Running SMJobBless..");

    result = (BOOL)SMJobBless(kSMDomainSystemLaunchd, (__bridge CFStringRef)label, authRef, &cfError);
    if (!result) {
        DDLogError(@"[ERROR] Could not install helper tool!");
        DDLogError(@"[ERROR] SMJobBless failed!");
        *error = CFBridgingRelease(cfError);
        DDLogError(@"[ERROR] %@", [*error localizedDescription]);
    }

    return result;
} // blessHelperWithLabel:authRef:error

- (void)showHelperToolInstallBox {

    // --------------------------------------------------------------
    //  Show box with "Install Helper" button just above build button
    // --------------------------------------------------------------
    [_viewInstallHelper setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_viewBuildInfo addSubview:_viewInstallHelper];
    [_viewBuildInfo addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_viewInstallHelper]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_viewInstallHelper)]];

    [_viewBuildInfo
        addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(3)-[_viewInstallHelper]-(3)-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_viewInstallHelper)]];
    [_buttonBuild setHidden:YES];
    [_buttonBuild setEnabled:NO];
} // showHelperToolInstallBox

- (void)showHelperToolUpgradeBox {

    // --------------------------------------------------------------
    //  Show box with "Upgrade Helper" button just above build button
    // --------------------------------------------------------------
    [_textFieldInstallHelperText setStringValue:@"To create a NetInstall Image you need to upgrade the helper."];
    [_buttonInstallHelper setTitle:@"Upgrade Helper"];
    [self showHelperToolInstallBox];
} // showHelperToolUpgradeBox

- (void)hideHelperToolInstallBox {

    // --------------------------------------------------------------
    //  Hide box with "Install/Upgrade Helper" button
    // --------------------------------------------------------------
    [_viewInstallHelper removeFromSuperview];
    [_buttonBuild setHidden:NO];
} // hideHelperToolInstallBox

- (void)checkHelperVersion {

    DDLogDebug(@"[DEBUG] Checking installed helper tool version...");

    // --------------------------------------------------------------
    //  Check that helper binary exists
    // --------------------------------------------------------------
    NSURL *libraryURL = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory inDomain:NSLocalDomainMask appropriateForURL:nil create:NO error:nil];
    NSURL *helperToolBinaryURL = [libraryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"PrivilegedHelperTools/%@", NBCBundleIdentifierHelper]];
    if (![helperToolBinaryURL checkResourceIsReachableAndReturnError:nil]) {
        [self setHelperAvailable:NO];
        [self showHelperToolInstallBox];
        [_buttonBuild setEnabled:NO];
        return;
    }

    // --------------------------------------------------------------
    //  Get version of helper within our bundle
    // --------------------------------------------------------------
    NSString *currentHelperToolBundlePath = [NSString stringWithFormat:@"Contents/Library/LaunchServices/%@", NBCBundleIdentifierHelper];
    NSURL *currentHelperToolURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:currentHelperToolBundlePath];
    NSDictionary *currentHelperToolInfoPlist = (NSDictionary *)CFBridgingRelease(CFBundleCopyInfoDictionaryForURL((CFURLRef)currentHelperToolURL));
    NSString *currentHelperToolBundleVersion = [currentHelperToolInfoPlist objectForKey:@"CFBundleVersion"];

    // --------------------------------------------------------------
    //  Connect to helper and get installed helper's version
    // --------------------------------------------------------------
    dispatch_queue_t taskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(taskQueue, ^{

      NBCHelperConnection *helperConnector = [[NBCHelperConnection alloc] init];
      [helperConnector connectToHelper];

      [[[helperConnector connection] remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
        DDLogError(@"%@", [proxyError localizedDescription]);

        // --------------------------------------------------------------
        //  If connection failed, require (re)install of helper tool
        // --------------------------------------------------------------
        [self setHelperAvailable:NO];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showHelperToolInstallBox];
          [self->_buttonBuild setEnabled:NO];
        });

      }] getVersionWithReply:^(NSString *version) {
        DDLogDebug(@"[DEBUG] Currently installed helper tool version: %@", version);

        // --------------------------------------------------------------
        //  If versions mismatch, require update of helper tool
        // --------------------------------------------------------------
        if (![currentHelperToolBundleVersion isEqualToString:version]) {
            DDLogInfo(@"A new version of the helper tool is available");

            [self setHelperAvailable:NO];
            dispatch_async(dispatch_get_main_queue(), ^{
              [self showHelperToolUpgradeBox];
              [self->_buttonBuild setEnabled:NO];
            });
        } else {
            DDLogDebug(@"[DEBUG] Installed helper tool is up to date.");
            [self setHelperAvailable:YES];
        }
      }];
    });
} // checkHelperVersion

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Reachability
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)testInternetConnection {
    NSString *hostToCheck = @"github.com";
    // --------------------------------------------------------------
    //  Check if connection against github.com is succesful
    // --------------------------------------------------------------
    _internetReachableFoo = [Reachability reachabilityWithHostname:hostToCheck];
    __unsafe_unretained typeof(self) weakSelf = self;

    // --------------------------------------------------------------
    //  Host IS reachable
    // --------------------------------------------------------------
    _internetReachableFoo.reachableBlock = ^(Reachability *reach) {
#pragma unused(reach)
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf hideNoInternetConnection];

        // --------------------------------------------------------------
        //  Check for updates to NBICreator
        // --------------------------------------------------------------
        if ([[[NSUserDefaults standardUserDefaults] objectForKey:NBCUserDefaultsCheckForUpdates] boolValue]) {
            [[NBCUpdater sharedUpdater] checkForUpdates];
        }
      });
    };

    // --------------------------------------------------------------
    //  Host is NOT reachable
    // --------------------------------------------------------------
    _internetReachableFoo.unreachableBlock = ^(Reachability *reach) {
#pragma unused(reach)
      DDLogDebug(@"Reachability: %@ is NOT reachable!", hostToCheck);
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf showNoInternetConnection];
      });
    };

    // --------------------------------------------------------------
    //  Start background notifier that will call above blocks if reachability changes
    // --------------------------------------------------------------
    [_internetReachableFoo startNotifier];
} // testInternetConnection

- (void)showNoInternetConnection {

    // --------------------------------------------------------------
    //  Show banner at top of application with text "No Internet Connection"
    // --------------------------------------------------------------
    [_viewNoInternetConnection setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_viewMainWindow addSubview:_viewNoInternetConnection positioned:NSWindowAbove relativeTo:nil];

    [_viewNoInternetConnection
        addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_viewNoInternetConnection(==20)]" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_viewNoInternetConnection)]];

    [_viewMainWindow
        addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_viewNoInternetConnection]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_viewNoInternetConnection)]];

    [_viewMainWindow
        addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_viewNoInternetConnection]" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_viewNoInternetConnection)]];
} // showNoInternetConnection

- (void)hideNoInternetConnection {
    [_viewNoInternetConnection removeFromSuperview];
} // hideNoInternetConnection

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UI Updates
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NSInteger)selectedSegment {
    return [_segmentedControlNBI selectedSegment];
} // selectedSegment

- (void)selectSegmentedControl:(NSInteger)selectedSegment {

    // --------------------------------------------------------------
    //  Add selected workflows views to main window placeholders
    // --------------------------------------------------------------
    if (selectedSegment == kSegmentedControlNetInstall) {
        if (!_niSettingsViewController) {
            _niSettingsViewController = [[NBCNetInstallSettingsViewController alloc] init];
        }

        if (_niSettingsViewController) {
            [self addViewToSettingsView:[_niSettingsViewController view]];
            _currentSettingsController = _niSettingsViewController;
        }

        if (!_niDropViewController) {
            _niDropViewController = [[NBCSourceDropViewController alloc] initWithDelegate:_niSettingsViewController];
            [_niDropViewController setSettingsViewController:_niSettingsViewController];
        }

        if (_niDropViewController) {
            [self addViewToDropView:[_niDropViewController view]];
        }
    } else if (selectedSegment == kSegmentedControlDeployStudio) {
        if (!_dsSettingsViewController) {
            _dsSettingsViewController = [[NBCDeployStudioSettingsViewController alloc] init];
        }

        if (_dsSettingsViewController) {
            [self addViewToSettingsView:[_dsSettingsViewController view]];
            _currentSettingsController = _dsSettingsViewController;
            [_currentSettingsController updateDeployStudioVersion];
        }

        if (!_dsDropViewController) {
            _dsDropViewController = [[NBCSourceDropViewController alloc] initWithDelegate:_dsSettingsViewController];
            [_dsDropViewController setSettingsViewController:_dsSettingsViewController];
        }

        if (_dsDropViewController) {
            [self addViewToDropView:[_dsDropViewController view]];
        }
    } else if (selectedSegment == kSegmentedControlImagr) {
        if (!_imagrSettingsViewController) {
            _imagrSettingsViewController = [[NBCImagrSettingsViewController alloc] init];
        }

        if (_imagrSettingsViewController) {
            [self addViewToSettingsView:[_imagrSettingsViewController view]];
            _currentSettingsController = _imagrSettingsViewController;
        }

        if (!_imagrDropViewController) {
            _imagrDropViewController = [[NBCSourceDropViewController alloc] initWithDelegate:_imagrSettingsViewController];
            [_imagrDropViewController setSettingsViewController:_imagrSettingsViewController];
        }

        if (_imagrDropViewController) {
            [self addViewToDropView:[_imagrDropViewController view]];
        }
    } else if (selectedSegment == kSegmentedControlCasper) {
        if (!_casperSettingsViewController) {
            _casperSettingsViewController = [[NBCCasperSettingsViewController alloc] init];
        }

        if (_casperSettingsViewController) {
            [self addViewToSettingsView:[_casperSettingsViewController view]];
            _currentSettingsController = _casperSettingsViewController;
        }

        if (!_casperDropViewController) {
            _casperDropViewController = [[NBCSourceDropViewController alloc] initWithDelegate:_casperSettingsViewController];
            [_casperDropViewController setSettingsViewController:_casperSettingsViewController];
        }

        if (_casperDropViewController) {
            [self addViewToDropView:[_casperDropViewController view]];
        }
    } else if (selectedSegment == kSegmentedControlCustom) {
        if (!_customSettingsViewController) {
            _customSettingsViewController = [[NBCCustomSettingsViewController alloc] init];
        }

        if (_customSettingsViewController) {
            [self addViewToSettingsView:[_customSettingsViewController view]];
            _currentSettingsController = _customSettingsViewController;
        }

        if (!_customDropViewController) {
            _customDropViewController = [[NBCSourceDropViewController alloc] initWithDelegate:_customSettingsViewController];
            [_customDropViewController setSettingsViewController:_customSettingsViewController];
        }

        if (_customDropViewController) {
            [self addViewToDropView:[_customDropViewController view]];
        }
    }

    // --------------------------------------------------------------
    //  Update menu bar items with correct connections to currently selected workflow
    // --------------------------------------------------------------
    [_menuItemNew setAction:@selector(menuItemNew:)];
    [_menuItemNew setTarget:[_currentSettingsController templates]];

    [_menuItemSave setAction:@selector(menuItemSave:)];
    [_menuItemSave setTarget:[_currentSettingsController templates]];

    [_menuItemSaveAs setAction:@selector(menuItemSaveAs:)];
    [_menuItemSaveAs setTarget:[_currentSettingsController templates]];

    [_menuItemRename setAction:@selector(menuItemRename:)];
    [_menuItemRename setTarget:[_currentSettingsController templates]];

    [_menuItemExport setAction:@selector(menuItemExport:)];
    [_menuItemExport setTarget:[_currentSettingsController templates]];

    [_menuItemDelete setAction:@selector(menuItemDelete:)];
    [_menuItemDelete setTarget:[_currentSettingsController templates]];

    [_menuItemShowInFinder setAction:@selector(menuItemShowInFinder:)];
    [_menuItemShowInFinder setTarget:[_currentSettingsController templates]];

    [_window setInitialFirstResponder:[_currentSettingsController textFieldNBIName]];

    // --------------------------------------------------------------
    //  Verify that the currently selected workflow is ready to build
    // --------------------------------------------------------------
    [_currentSettingsController verifyBuildButton];
} // selectSegmentedControl

- (void)addViewToSettingsView:(NSView *)settingsView {

    // --------------------------------------------------------------
    //  Remove current view(s) from settings view placeholder
    // --------------------------------------------------------------
    NSArray *currentSubviews = [_viewNBISettings subviews];
    for (NSView *view in currentSubviews) {
        [view removeFromSuperview];
    }

    // --------------------------------------------------------------
    //  Add selected workflows settings view to settings view placeholder
    // --------------------------------------------------------------
    [_viewNBISettings addSubview:settingsView];
    [settingsView setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSArray *constraintsArray;
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"|[settingsView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(settingsView)];
    [_viewNBISettings addConstraints:constraintsArray];
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[settingsView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(settingsView)];
    [_viewNBISettings addConstraints:constraintsArray];
} // addViewToSettingsView

- (void)addViewToDropView:(NSView *)dropView {

    // --------------------------------------------------------------
    //  Remove current view(s) from drop view placeholder
    // --------------------------------------------------------------
    NSArray *currentSubviews = [[_viewDropView subviews] copy];
    for (NSView *view in currentSubviews) {
        [view removeFromSuperview];
    }

    // --------------------------------------------------------------
    //  Add selected workflows drop view to drop view placeholder
    // --------------------------------------------------------------
    [_viewDropView addSubview:dropView];
    [dropView setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSArray *constraintsArray;
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"|[dropView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(dropView)];
    [_viewDropView addConstraints:constraintsArray];
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[dropView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(dropView)];
    [_viewDropView addConstraints:constraintsArray];
} // addViewToDropView

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IBActions
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (IBAction)buttonInstallHelper:(id)__unused sender {
    NSError *error = nil;
    if ([self installHelper:&error]) {
        [self setHelperAvailable:YES];
        [_currentSettingsController verifyBuildButton];
        [self hideHelperToolInstallBox];
    } else {
        DDLogError(@"[ERROR] %@", [error localizedDescription]);
    }
} // buttonInstallHelper

- (void)continueWorkflow:(NSDictionary *)preWorkflowTasks {
    [_currentSettingsController buildNBI:preWorkflowTasks];
} // continueWorkflow

- (IBAction)buttonBuild:(id)__unused sender {

    DDLogDebug(@"[DEBUG] Button pressed: 'Build'");
    if ([NSEvent modifierFlags] & NSAlternateKeyMask) {

        DDLogDebug(@"[DEBUG] Modifier key 'Alt': YES");
        if (_optionBuildPanel) {
            [self setOptionBuildPanel:nil];
        }
        [self setOptionBuildPanel:[[NBCOptionBuildPanel alloc] initWithDelegate:self]];

        if (_currentSettingsController) {
            [_optionBuildPanel setSettingsViewController:_currentSettingsController];
        } else {
            DDLogError(@"[ERROR] Current settings controller was nil!");
            return;
        }

        [[(NBCController *)[[NSApplication sharedApplication] delegate] window] beginSheet:[_optionBuildPanel window]
                            completionHandler:^(NSModalResponse returnCode) {
                              if (returnCode == NSModalResponseCancel) {
                                  DDLogInfo(@"[DEBUG] Workflow canceled!");
                              }
                            }];
    } else {
        DDLogDebug(@"[DEBUG] Modifier key 'Alt': NO");
        DDLogDebug(@"[DEBUG] Sending -(void)buildNBI to selected settings controller: %@", _currentSettingsController);
        if ([_currentSettingsController respondsToSelector:@selector(buildNBI:)]) {
            [_currentSettingsController buildNBI:@{}];
        } else {
            DDLogError(@"[ERROR] Settings controller: %@ doesn't respond to -(void)buildNBI:", _currentSettingsController);
        }
    }
} // buttonBuild

- (IBAction)segmentedControlNBI:(id)sender {
    NSSegmentedControl *segmentedControl = (NSSegmentedControl *)sender;
    [self selectSegmentedControl:[segmentedControl selectedSegment]];
} // segmentedControlNBI

- (IBAction)menuItemPreferences:(id)__unused sender {
    if (!_preferencesWindow) {
        [self setPreferencesWindow:[[NBCPreferences alloc] initWithWindowNibName:@"NBCPreferences"]];
    }
    [_preferencesWindow updateCacheFolderSize];
    [[_preferencesWindow window] makeKeyAndOrderFront:self];
} // menuItemPreferences

- (IBAction)menuItemHelp:(id)__unused sender {
    DDLogInfo(@"Opening help URL: %@", NBCHelpURL);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NBCHelpURL]];
} // menuItemHelp

- (IBAction)menuItemMainWindow:(id)sender {
#pragma unused(sender)
    if (_window) {
        [_window makeKeyAndOrderFront:self];
    }
} // menuItemMainWindow

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCWorkflowProgressDelegate
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateProgressStatus:(NSString *)statusMessage workflow:(id)workflow {
#pragma unused(statusMessage, workflow)
}
- (void)updateProgressStatus:(NSString *)statusMessage {
#pragma unused(statusMessage)
}
- (void)updateProgressBar:(double)value {
#pragma unused(value)
}
- (void)incrementProgressBar:(double)value {
#pragma unused(value)
}
- (void)logDebug:(NSString *)logMessage {
    DDLogDebug(@"[DEBUG] %@", logMessage);
}
- (void)logInfo:(NSString *)logMessage {
    DDLogInfo(@"%@", logMessage);
}
- (void)logWarn:(NSString *)logMessage {
    DDLogWarn(@"[WARN] %@", logMessage);
}
- (void)logError:(NSString *)logMessage {
    DDLogError(@"[ERROR] %@", logMessage);
}
- (void)logStdOut:(NSString *)stdOutString {
    DDLogDebug(@"[DEBUG][stdout] %@", stdOutString);
}
- (void)logStdErr:(NSString *)stdErrString {
    DDLogDebug(@"[DEBUG][stderr] %@", stdErrString);
}
- (void)logLevel:(void (^)(int))reply {
    reply((int)ddLogLevel);
}

@end
