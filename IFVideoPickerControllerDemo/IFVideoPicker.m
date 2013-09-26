//
//  IFVideoPicker.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 3/25/13.
//  Copyright (c) 2013 iFactory Lab Limited. All rights reserved.
//

#import "IFVideoPicker.h"

@interface IFVideoPicker () <AVCaptureVideoDataOutputSampleBufferDelegate> {
  AVCaptureSession *session_;
  id deviceConnectedObserver;
  id deviceDisconnectedObserver;
  captureHandler sampleBufferHandler_;
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position;
- (AVCaptureDevice *)frontFacingCamera;
- (AVCaptureDevice *)backFacingCamera;
- (AVCaptureDevice *)audioDevice;

@end

// Safe release
#define SAFE_RELEASE(x) if (x) { [x release]; x = nil; }

#pragma mark -

@implementation IFVideoPicker

const char *VideoBufferQueueLabel = "com.ifactorylab.ifvideopicker.queue";

@synthesize videoInput;
@synthesize audioInput;
@synthesize bufferOutput;
@synthesize captureVideoPreviewLayer;
@synthesize videoPreviewView;
@synthesize isCapturing;

- (id)init {
  self = [super init];
  if (self !=  nil) {
    self.isCapturing = NO;
    __block id weakSelf = self;
    void (^deviceConnectedBlock)(NSNotification *) = ^(NSNotification *notification) {
      AVCaptureDevice *device = [notification object];
      
      BOOL sessionHasDeviceWithMatchingMediaType = NO;
			NSString *deviceMediaType = nil;
			if ([device hasMediaType:AVMediaTypeAudio]) {
        deviceMediaType = AVMediaTypeAudio;
      } else if ([device hasMediaType:AVMediaTypeVideo]) {
        deviceMediaType = AVMediaTypeVideo;
      }
      
      if (deviceMediaType != nil && session_ != nil) {
				for (AVCaptureDeviceInput *input in [session_ inputs]) {
					if ([[input device] hasMediaType:deviceMediaType]) {
						sessionHasDeviceWithMatchingMediaType = YES;
						break;
					}
				}
				
				if (!sessionHasDeviceWithMatchingMediaType) {
					NSError	*error;
					AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
					if ([session_ canAddInput:input])
						[session_ addInput:input];
				}
			}
			
      /**
       if ([delegate respondsToSelector:@selector(captureManagerDeviceConfigurationChanged:)]) {
       [delegate captureManagerDeviceConfigurationChanged:self];
       }
       */

    };
    
    void (^deviceDisconnectedBlock)(NSNotification *) = ^(NSNotification *notification) {
      AVCaptureDevice *device = [notification object];
			
			if ([device hasMediaType:AVMediaTypeAudio]) {
        if (session_) {
          [session_ removeInput:[weakSelf audioInput]];
        }
        [weakSelf setAudioInput:nil];
			}
			else if ([device hasMediaType:AVMediaTypeVideo]) {
        if (session_) {
          [session_ removeInput:[weakSelf videoInput]];
        }
				[weakSelf setVideoInput:nil];
			}
/*
			if ([delegate respondsToSelector:@selector(captureManagerDeviceConfigurationChanged:)]) {
				[delegate captureManagerDeviceConfigurationChanged:self];
			}
*/
    };
    
    // Create capture device with video input
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    deviceConnectedObserver =
      [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
                                      object:nil
                                       queue:nil
                                  usingBlock:deviceConnectedBlock];
    deviceDisconnectedObserver =
      [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                                      object:nil
                                       queue:nil
                                  usingBlock:deviceDisconnectedBlock];
  }
  return self;
}

- (void)dealloc {
  [self shutdown];
  
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:deviceConnectedObserver];
  [notificationCenter removeObserver:deviceDisconnectedObserver];

  SAFE_RELEASE(session)
  SAFE_RELEASE(videoInput)
  SAFE_RELEASE(audioInput)
  [super dealloc];
}

- (BOOL)startup {
  if (session != nil) {
    // If session already exists, return NO.
    NSLog(@"Video session already exists, you must call shutdown current session first");
    return NO;
  }
  
  // Set torch and flash mode to auto
  // We use back facing camera by default
  if ([[self backFacingCamera] hasFlash]) {
    if ([[self backFacingCamera] lockForConfiguration:nil]) {
			if ([[self backFacingCamera] isFlashModeSupported:AVCaptureFlashModeAuto]) {
				[[self backFacingCamera] setFlashMode:AVCaptureFlashModeAuto];
			}
			[[self backFacingCamera] unlockForConfiguration];
		}
  }
  
  if ([[self backFacingCamera] hasTorch]) {
    if ([[self backFacingCamera] lockForConfiguration:nil]) {
			if ([[self backFacingCamera] isTorchModeSupported:AVCaptureTorchModeAuto]) {
				[[self backFacingCamera] setTorchMode:AVCaptureTorchModeAuto];
			}
			[[self backFacingCamera] unlockForConfiguration];
		}
  }
  
  // Init the device inputs
  AVCaptureDeviceInput *newVideoInput =
      [[AVCaptureDeviceInput alloc] initWithDevice:[self backFacingCamera]
                                             error:nil];
  AVCaptureDeviceInput *newAudioInput =
      [[AVCaptureDeviceInput alloc] initWithDevice:[self audioDevice]
                                             error:nil];
  
  // Set up the video YUV buffer output for
  dispatch_queue_t bufferCaptureQueue =
      dispatch_queue_create(VideoBufferQueueLabel, DISPATCH_QUEUE_SERIAL);
  AVCaptureVideoDataOutput *newBufferOutput = [[AVCaptureVideoDataOutput alloc] init];
  [newBufferOutput setSampleBufferDelegate:self queue:bufferCaptureQueue];
  
  NSDictionary *videoSettings =
      [NSDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
        kCVPixelBufferPixelFormatTypeKey, nil];
  bufferOutput.videoSettings = videoSettings;
  
  // Create session (use default AVCaptureSessionPresetHigh)
  session_ = [[AVCaptureSession alloc] init];
  
  // Add inputs and output to the capture session
  if ([session_ canAddInput:newVideoInput]) {
    [session_ addInput:newVideoInput];
  }
  
  if ([session_ canAddInput:newAudioInput]) {
    [session_ addInput:newAudioInput];
  }

  [self setVideoInput:newVideoInput];
  [self setAudioInput:newAudioInput];
  [self setBufferOutput:newBufferOutput];

  [newVideoInput release];
  [newAudioInput release];
  [newBufferOutput release];
  
  return YES;
}

- (void)shutdown {
  [self stopCapture];
  [self stopPreview];
}

- (void)startPreview:(UIView *)view {
  [self startPreview:view withFrame:[view bounds]];
}

- (void)startPreview:(UIView *)view withFrame:(CGRect)frame {
  AVCaptureVideoPreviewLayer *newCaptureVideoPreviewLayer =
      [[AVCaptureVideoPreviewLayer alloc] initWithSession:session_];
  
  CALayer *viewLayer = [view layer];
  [viewLayer setMasksToBounds:YES];
  
  [newCaptureVideoPreviewLayer setFrame:frame];
  if ([newCaptureVideoPreviewLayer respondsToSelector:@selector(connection)]) {
    if ([newCaptureVideoPreviewLayer.connection isVideoOrientationSupported]) {
      [newCaptureVideoPreviewLayer.connection
          setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }
  } else {
    // Deprecated in 6.0; here for backward compatibility
    if ([newCaptureVideoPreviewLayer isOrientationSupported]) {
      [newCaptureVideoPreviewLayer
          setOrientation:AVCaptureVideoOrientationPortrait];
    }
  }
  
  [newCaptureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
  [viewLayer insertSublayer:newCaptureVideoPreviewLayer
                      below:[[viewLayer sublayers]
                             objectAtIndex:0]];
  
  [self setVideoPreviewView:view];
  [self setCaptureVideoPreviewLayer:newCaptureVideoPreviewLayer];
  [newCaptureVideoPreviewLayer release];
  
  // Start the session. This is done asychronously since -startRunning doesn't return until the session is running.
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [session_ startRunning];
  });
}

- (void)stopPreview {
  if (session_ == nil) {
    // Session has not created yet...
    return;
  }
  
  if (session_.isRunning) {
    // There is no active session running...
    NSLog(@"You need to run startPreview first");
    return;
  }
  
  [session_ stopRunning];
  
  SAFE_RELEASE(captureVideoPreviewLayer)
  SAFE_RELEASE(videoPreviewView)
  SAFE_RELEASE(session_)
}

// Find a camera with the specificed AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position {
  NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
  for (AVCaptureDevice *device in devices) {
    if ([device position] == position) {
      return device;
    }
  }
  return nil;
}

// Find a front facing camera, returning nil if one is not found
- (AVCaptureDevice *)frontFacingCamera {
  return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

// Find a back facing camera, returning nil if one is not found
- (AVCaptureDevice *) backFacingCamera {
  return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

// Find and return an audio device, returning nil if one is not found
- (AVCaptureDevice *)audioDevice {
  NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
  if ([devices count] > 0) {
    return [devices objectAtIndex:0];
  }
  return nil;
}

- (void)startCaptureWithBlock:(captureHandler)completionBlock {
   if ([session_ canAddOutput:self.bufferOutput]) {
     [session_ addOutput:self.bufferOutput];
   }
  
  sampleBufferHandler_ = completionBlock;
  [self setIsCapturing:YES];
}

- (void)stopCapture {
  if (!self.isCapturing) {
    return;
  }
  
  [session_ removeOutput:self.bufferOutput];
  sampleBufferHandler_ = nil;
  [self setIsCapturing:NO];
}

#pragma mark -
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void) captureOutput:(AVCaptureOutput *)captureOutput
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection {
  if (sampleBufferHandler_ != nil) {
    sampleBufferHandler(sampleBuffer);
  }
}

@end
