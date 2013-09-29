//
//  IFAVAssetBaseEncoder.h
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 9/27/13.
//  Copyright (c) 2013 Min Kim. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface IFAVAssetBaseEncoder : NSObject

@property (atomic, retain) AVAssetWriter *assetWriter;
@property (atomic, retain) NSString *filePath;

@end
