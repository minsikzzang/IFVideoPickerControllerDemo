//
//  ViewController.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 3/25/13.
//  Copyright (c) 2013 iFactory Lab Limited. All rights reserved.
//

#import "ViewController.h"
#import "IFVideoPicker.h"
#import "IFAudioEncoder.h"
#import "IFVideoEncoder.h"

@interface ViewController () {
  IFVideoPicker *videoPicker_;
}

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
  
  videoPicker_ = [[IFVideoPicker alloc] init];
  [videoPicker_ startup];
  [videoPicker_ startPreview:self.view];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)recordButtonPushed:(id)sender {
  if (videoPicker_.isCapturing) {
    self.textView.text = @"";
    [videoPicker_ stopCapture];
  } else {
    self.textView.text = @"Recording...";
    
    // audio 320kbos, samplerate 44100
    IFAudioEncoder *ae =
        [IFAudioEncoder createAACAudioWithBitRate:320000 sampleRate:44100];
    
    // video 500kbps, 512x288
    CMVideoDimensions dimensions;
    dimensions.width = 512;
    dimensions.height = 288;
    
    IFVideoEncoder *ve =
        [IFVideoEncoder createH264VideoWithDimensions:dimensions
                                              bitRate:500000
                                          maxKeyFrame:200];
    [videoPicker_ startCaptureWithEncoder:ve audio:ae captureBlock:^{
      
    }];
    
    /*
    [videoPicker_ startCaptureWithBlock:^(CMSampleBufferRef sampleBuffer,
                                          IFCapturedBufferType type) {
      CMFormatDescriptionRef formatDescription =
          CMSampleBufferGetFormatDescription(sampleBuffer);
      if (type == kBufferVideo) {
        CMVideoDimensions videoDementions =
            CMVideoFormatDescriptionGetDimensions(formatDescription);
        // CMVideoCodecType videoType = CMFormatDescriptionGetMediaSubType(formatDescription);
        
        NSLog(@"Video stream coming, %dx%d", videoDementions.width,
              videoDementions.height);
      } else if (type == kBufferAudio) {
        NSLog(@"Audio stream coming");
      }
    }];
     */
  }
}

- (void)dealloc {
  if (videoPicker_ != nil) {
    [videoPicker_ release];
  }
  
  [_textView release];
  [_textView release];
  [super dealloc];
}
@end
