//
//  IFAVAssetBaseEncoder.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 9/27/13.
//  Copyright (c) 2013 Min Kim. All rights reserved.
//

#import "IFAVAssetBaseEncoder.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface IFAVAssetBaseEncoder () {
}

- (NSString *)getEncodedFileName;

@end

@implementation IFAVAssetBaseEncoder

static const NSInteger kMaxTempFileLength = 1024 * 1024 * 5; // max file size
NSString *const kAVAssetEncodedOutput = @"ifavassetout.mp4";

@synthesize assetWriter;
@synthesize filePath;

- (id)init {
  self = [super init];
  if (self != nil) {
    // Generate temporary file path to store encoded file
    self.filePath = [self getEncodedFileName];
    
    NSError *error = nil;
    self.assetWriter =
        [[AVAssetWriter alloc] initWithURL:[NSURL URLWithString:self.filePath]
                                  fileType:(NSString *)kUTTypeMPEG4
                                     error:&error];
    if (error) {
      // [self showError:error];
    }


  }
  return self;
}

- (NSString *)getEncodedFileName {
  return kAVAssetEncodedOutput;
}

- (void)dealloc {
  [assetWriter release];
  [filePath release];
  [super dealloc];
}

@end
