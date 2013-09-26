//
//  IFVideoPicker.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 3/25/13.
//  Copyright (c) 2013 iFactory Lab Limited. All rights reserved.
//

#import "IFVideoPicker.h"

@interface IFVideoPicker () <AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate> {
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

const char *VideoBufferQueueLabel = "com.ifactorylab.ifvideopicker.videoqueue";
const char *AudioBufferQueueLabel = "com.ifactorylab.ifvideopicker.audioqueue";

@synthesize videoInput;
@synthesize audioInput;
@synthesize videoBufferOutput;
@synthesize audioBufferOutput;
@synthesize captureVideoPreviewLayer;
@synthesize videoPreviewView;
@synthesize isCapturing;
@synthesize session;

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
      
      if (deviceMediaType != nil && session != nil) {
				for (AVCaptureDeviceInput *input in [self.session inputs]) {
					if ([[input device] hasMediaType:deviceMediaType]) {
						sessionHasDeviceWithMatchingMediaType = YES;
						break;
					}
				}
				
				if (!sessionHasDeviceWithMatchingMediaType) {
					NSError	*error;
					AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
					if ([self.session canAddInput:input])
						[self.session addInput:input];
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
        if (self.session) {
          [self.session removeInput:[weakSelf audioInput]];
        }
        [weakSelf setAudioInput:nil];
			}
			else if ([device hasMediaType:AVMediaTypeVideo]) {
        if (self.session) {
          [self.session removeInput:[weakSelf videoInput]];
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
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:deviceConnectedObserver];
  [notificationCenter removeObserver:deviceDisconnectedObserver];

  [self shutdown];
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
  
  // Set up the video YUV buffer output
  dispatch_queue_t videoCaptureQueue =
      dispatch_queue_create(VideoBufferQueueLabel, DISPATCH_QUEUE_SERIAL);
  
  AVCaptureVideoDataOutput *newVideoOutput = [[AVCaptureVideoDataOutput alloc] init];
  [newVideoOutput setSampleBufferDelegate:self queue:videoCaptureQueue];
  
  // or kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ??
  NSDictionary *videoSettings =
      [NSDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
        kCVPixelBufferPixelFormatTypeKey, nil];
  newVideoOutput.videoSettings = videoSettings;
  
  // Set up the audio buffer output
  dispatch_queue_t audioCaptureQueue =
      dispatch_queue_create(AudioBufferQueueLabel, DISPATCH_QUEUE_SERIAL);

  AVCaptureAudioDataOutput *newAudioOutput = [[AVCaptureAudioDataOutput alloc] init];
  [newAudioOutput setSampleBufferDelegate:self queue:audioCaptureQueue];
  
  // Create session (use default AVCaptureSessionPresetHigh)
  AVCaptureSession *newSession = [[AVCaptureSession alloc] init];
  // newSession.sessionPreset = AVCaptureSessionPreset640x480;
  // If you want to have HD quality output, use this code below
  newSession.sessionPreset = AVCaptureSessionPresetiFrame960x540;
  
  // Add inputs and output to the capture session
  if ([newSession canAddInput:newVideoInput]) {
    [newSession addInput:newVideoInput];
  }
  
  if ([newSession canAddInput:newAudioInput]) {
    [newSession addInput:newAudioInput];
  }

  [self setSession:newSession];
  [self setVideoInput:newVideoInput];
  [self setAudioInput:newAudioInput];
  [self setVideoBufferOutput:newVideoOutput];
  [self setAudioBufferOutput:newAudioOutput];
  
  [newSession release];
  [newVideoInput release];
  [newAudioInput release];
  [newVideoOutput release];
  [newAudioOutput release];
  
  return YES;
}

- (void)shutdown {
  [self stopCapture];
  [self stopPreview];
  
  SAFE_RELEASE(session)
  SAFE_RELEASE(videoBufferOutput)
  SAFE_RELEASE(audioBufferOutput)
  SAFE_RELEASE(videoInput)
  SAFE_RELEASE(audioInput)
}

- (void)startPreview:(UIView *)view {
  [self startPreview:view withFrame:[view bounds]];
}

- (void)startPreview:(UIView *)view withFrame:(CGRect)frame {
  AVCaptureVideoPreviewLayer *newCaptureVideoPreviewLayer =
      [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
  
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
    [self.session startRunning];
  });
}

- (void)stopPreview {
  if (self.session == nil) {
    // Session has not created yet...
    return;
  }
  
  if (self.session.isRunning) {
    // There is no active session running...
    NSLog(@"You need to run startPreview first");
    return;
  }
  
  [self.session stopRunning];
  
  SAFE_RELEASE(captureVideoPreviewLayer)
  SAFE_RELEASE(videoPreviewView)
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
  // add video and audio output to current capture session.
  if ([self.session canAddOutput:self.videoBufferOutput]) {
     [self.session addOutput:self.videoBufferOutput];
  }
  
  if ([self.session canAddOutput:self.audioBufferOutput]) {
    [self.session addOutput:self.audioBufferOutput];
  }
  
  sampleBufferHandler_ = completionBlock;
  
  // Now, we are capturing
  [self setIsCapturing:YES];
}

- (void)stopCapture {
  if (!self.isCapturing) {
    return;
  }
  
  // Pull out video and audio output from current capture session.
  [self.session removeOutput:self.videoBufferOutput];
  [self.session removeOutput:self.audioBufferOutput];
  
  sampleBufferHandler_ = nil;
  
  // Now, we are not capturing
  [self setIsCapturing:NO];
}

#pragma mark -
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void) captureOutput:(AVCaptureOutput *)captureOutput
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection {
  CMFormatDescriptionRef formatDescription =
      CMSampleBufferGetFormatDescription(sampleBuffer);
  
  if (connection == [videoBufferOutput connectionWithMediaType:AVMediaTypeVideo]) {
    // CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMVideoDimensions videoDementions =
        CMVideoFormatDescriptionGetDimensions(formatDescription);
    // CMVideoCodecType videoType = CMFormatDescriptionGetMediaSubType(formatDescription);
    
    NSLog(@"Video stream coming, %dx%d", videoDementions.width,
          videoDementions.height);
  } else if (connection == [audioBufferOutput connectionWithMediaType:AVMediaTypeAudio]) {
    NSLog(@"Audio stream coming");
  }
  
  /*
  if (sampleBufferHandler_ != nil) {
    sampleBufferHandler_(sampleBuffer);
  }
   */
}

@end
