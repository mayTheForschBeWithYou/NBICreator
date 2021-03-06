//
//  NBCDesktopEntity.m
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

#import "NBCDesktopEntity.h"

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopEntity

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Init / Dealloc
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (id)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _fileURL = fileURL;
    }
    return self;
} // initWithFileURL

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSPasteboardReading
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSString *)type {
    NSURL *url = [[NSURL alloc] initWithPasteboardPropertyList:propertyList ofType:type];
    self = [NBCDesktopEntity entityForURL:url];
    return self;
} // initWithPasteboardPropertyList

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
#pragma unused(pasteboard)
    return @[ (id)kUTTypeFolder, (id)kUTTypeFileURL ];
} // readableTypesForPasteboard

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
#pragma unused(type, pasteboard)
    return NSPasteboardReadingAsString;
} // readableTypesForPasteboard

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

+ (NBCDesktopEntity *)entityForURL:(NSURL *)url {
    NSString *typeIdentifier;
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    if ([url getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:nil]) {
        // --------------------------------------------------------------
        //  If url points to a certificate, allocate a NBCDesktopCertificateEntity
        // --------------------------------------------------------------
        if ([@[ @"public.x509-certificate" ] containsObject:typeIdentifier]) {
            return [[NBCDesktopCertificateEntity alloc] initWithFileURL:url];

            // --------------------------------------------------------------
            //  If url points to a installer package, allocate a NBCDesktopPackageEntity
            // --------------------------------------------------------------
        } else if ([@[ @"com.apple.installer-package-archive" ] containsObject:typeIdentifier]) {
            return [[NBCDesktopPackageEntity alloc] initWithFileURL:url];

            // --------------------------------------------------------------
            //  If url points to a configuration profile, allocate a NBCDesktopConfigurationProfileEntity
            // --------------------------------------------------------------
        } else if ([@[ @"com.apple.mobileconfig" ] containsObject:typeIdentifier]) {
            return [[NBCDesktopConfigurationProfileEntity alloc] initWithFileURL:url];

            // --------------------------------------------------------------
            //  If url points to a script, allocate a NBCDesktopScriptEntity
            // --------------------------------------------------------------
        } else if ([workspace type:typeIdentifier conformsToType:@"public.shell-script"]) {
            return [[NBCDesktopScriptEntity alloc] initWithFileURL:url];

            // --------------------------------------------------------------
            //  If url points to a folder, allocate a NBCDesktopFolderEntity
            // --------------------------------------------------------------
        } else if ([typeIdentifier isEqualToString:(NSString *)kUTTypeFolder]) {
            return [[NBCDesktopFolderEntity alloc] initWithFileURL:url];
        }
    }
    return nil;
} // entityForURL

- (NSString *)name {
    NSString *name;
    if ([_fileURL getResourceValue:&name forKey:NSURLLocalizedNameKey error:nil]) {
        return name;
    }
    return nil;
} // name

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopCertificateEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopCertificateEntity

- (NSData *)certificate {
    if (!_certificate) {

        // --------------------------------------------------------------
        //  Try reading file contents as string (PEM-encoding)
        // --------------------------------------------------------------
        NSMutableString *certificateString = [NSMutableString stringWithContentsOfURL:[self fileURL] encoding:NSUTF8StringEncoding error:nil];
        if ([certificateString length] != 0) {

            /*/////////////////////////////////////////////////////////////////////////////////
             /// FUTURE FUNCTIONALITY - CHECK IF FILE/STRING CONTAINS MULTIPLE CERTIFICATES ///
             ////////////////////////////////////////////////////////////////////////////////*/

            // --------------------------------------------------------------
            //  Remove "begin" and "end" lines from certificate
            // --------------------------------------------------------------
            [certificateString setString:[certificateString stringByReplacingOccurrencesOfString:@"-----BEGIN CERTIFICATE-----" withString:@""]];
            [certificateString setString:[certificateString stringByReplacingOccurrencesOfString:@"-----END CERTIFICATE-----" withString:@""]];

            // --------------------------------------------------------------
            //  Read in base64 string as certificate data
            // --------------------------------------------------------------
            _certificate = [[NSData alloc] initWithBase64EncodedString:certificateString options:NSDataBase64DecodingIgnoreUnknownCharacters];
        } else {

            // --------------------------------------------------------------
            //  Read in file contents as certificate data (DER-encoding)
            // --------------------------------------------------------------
            _certificate = [[NSData alloc] initWithContentsOfURL:self.fileURL];
        }
    }
    return _certificate;
} // certificate

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopPackageEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopPackageEntity

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopScriptEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopScriptEntity

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopConfigurationProfileEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopConfigurationProfileEntity

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NBCDesktopFolderEntity Implementation
#pragma mark -
////////////////////////////////////////////////////////////////////////////////
@implementation NBCDesktopFolderEntity

@end
