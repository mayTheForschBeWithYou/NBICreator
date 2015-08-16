//
//  NBCDropViewImage.m
//  NBICreator
//
//  Created by Erik Berglund on 2015-03-07.
//  Copyright (c) 2015 NBICreator. All rights reserved.
//

#import "NBCDeployStudioDropViewImage.h"
#import "NBCConstants.h"
#import "NBCLogging.h"

DDLogLevel ddLogLevel;

@implementation NBCDeployStudioDropViewImageBackground

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self registerForDraggedTypes:[NSImage imageTypes]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if ([NSImage canInitWithPasteboard:[sender draggingPasteboard]] && [sender draggingSourceOperationMask] & NSDragOperationCopy ) {
        NSURL *draggedFileURL = [self getDraggedSourceURLFromPasteboard:[sender draggingPasteboard]];
        if ( draggedFileURL ) {
            return NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    DDLogDebug(@"%@", NSStringFromSelector(_cmd));
    NSURL *draggedFileURL = [self getDraggedSourceURLFromPasteboard:[sender draggingPasteboard]];
    if ( draggedFileURL ) {
        NSDictionary * userInfo = @{ NBCNotificationUpdateNBIBackgroundUserInfoIconURL : draggedFileURL };
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:NBCNotificationDeployStudioUpdateNBIBackground object:self userInfo:userInfo];
        return YES;
    } else {
        return NO;
    }
}

- (NSURL *)getDraggedSourceURLFromPasteboard:(NSPasteboard *)pboard {
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        
        // ---------------------------------
        //  Verify only one item is dropped
        // ---------------------------------
        if ( [files count] != 1 ) {
            return nil;
        } else {
            
            NSURL *draggedFileURL = [NSURL fileURLWithPath:[files firstObject]];
            return draggedFileURL;
        }
    }
    return nil;
}

@end

@implementation NBCDeployStudioDropViewImageIcon

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self registerForDraggedTypes:[NSImage imageTypes]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if ([NSImage canInitWithPasteboard:[sender draggingPasteboard]] && [sender draggingSourceOperationMask] & NSDragOperationCopy ) {
        NSURL *draggedFileURL = [self getDraggedSourceURLFromPasteboard:[sender draggingPasteboard]];
        
        // ----------------------------------------------
        //  Only accept a URL if it has a icns extension
        // ----------------------------------------------
        NSString *draggedFileExtension = [draggedFileURL pathExtension];
        if ( draggedFileURL && [draggedFileExtension isEqualToString:@"icns"]) {
            return NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    DDLogDebug(@"%@", NSStringFromSelector(_cmd));
    NSURL *draggedFileURL = [self getDraggedSourceURLFromPasteboard:[sender draggingPasteboard]];
    if ( draggedFileURL ) {
        NSDictionary * userInfo = @{ NBCNotificationUpdateNBIIconUserInfoIconURL : draggedFileURL };
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:NBCNotificationDeployStudioUpdateNBIIcon object:self userInfo:userInfo];
        
        return YES;
    } else {
        return NO;
    }
}

- (NSURL *)getDraggedSourceURLFromPasteboard:(NSPasteboard *)pboard {
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        
        // ---------------------------------
        //  Verify only one item is dropped
        // ---------------------------------
        if ( [files count] != 1 ) {
            return nil;
        } else {
            
            NSURL *draggedFileURL = [NSURL fileURLWithPath:[files firstObject]];
            return draggedFileURL;
        }
    }
    return nil;
}

@end