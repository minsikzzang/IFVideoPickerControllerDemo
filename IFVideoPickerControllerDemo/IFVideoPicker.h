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

typedef void (^captureHandler)(CMSampleBufferRef sampleBuffer);

@interface IFVideoPicker : NSObject {
  
}

@property (nonatomic, retain) AVCaptureDeviceInput *videoInput;
@property (nonatomic, retain) AVCaptureDeviceInput *audioInput;
@property (nonatomic, retain) AVCaptureVideoDataOutput *bufferOutput;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property (nonatomic, retain) UIView *videoPreviewView;
@property (nonatomic, assign) BOOL isCapturing;

- (BOOL)startup;

- (void)shutdown;

/**
 @abstract
  start preview of camera input
 
 @param captureOutput

 */
- (void)startPreview:(UIView *)view;

- (void)startPreview:(UIView *)view withFrame:(CGRect)frame;

/**
 */
- (void)startCaptureWithBlock:(captureHandler)completionBlock;

/**
 */
- (void)stopCapture;

/**
 */
- (void)stopPreview;


@end
