//
//  IFVideoPicker.h
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 9/25/13.
//  Copyright (c) 2013 Min Kim. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVCaptureSession.h"
#import "AVFoundation/AVCaptureOutput.h"
#import "AVFoundation/AVCaptureDevice.h"
#import "AVFoundation/AVCaptureInput.h"
#import "AVFoundation/AVCaptureVideoPreviewLayer.h"
#import "AVFoundation/AVMediaFormat.h"

@interface IFVideoPicker : NSObject {
  
}

/**
 * Init with the given IFVideoPickerDelegate.
 */
- (id)initWithDelegate:(IFVideoPickerDelegate *)delegate;

// - (void)startWithBlock:(xxx)startHandler;

// - (void)stopWithBlock:(xxx)stopHandler;



@end
