//
//  ViewController.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 9/25/13.
//  Copyright (c) 2013 Min Kim. All rights reserved.
//

#import "ViewController.h"
#import "IFVideoPicker.h"

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
    [videoPicker_ startCaptureWithBlock:^(CMSampleBufferRef sampleBuffer) {
      NSLog(@"I've got some buffers");
    }];
  }
}

- (void)dealloc {
  [_textView release];
  [_textView release];
  [super dealloc];
}
@end
