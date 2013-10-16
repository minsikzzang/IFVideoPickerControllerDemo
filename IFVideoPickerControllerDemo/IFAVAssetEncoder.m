//
//  IFAVAssetEncoder.m
//  IFVideoPickerControllerDemo
//
//  Created by Min Kim on 9/27/13.
//  Copyright (c) 2013 Min Kim. All rights reserved.
//

#import "IFAVAssetEncoder.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVAssetExportSession.h>
#import <AVFoundation/AVMediaFormat.h>
#import "IFAudioEncoder.h"
#import "IFVideoEncoder.h"
#import "NSData+Hex.h"
#import "MP4Reader.h"

@interface IFAVAssetEncoder () {
  IFVideoEncoder *videoEncoder_;
  IFAudioEncoder *audioEncoder_;
  MP4Reader *mp4Reader_;
  NSMutableArray *timeStamps_;
  int firstPts_;
  
  dispatch_queue_t assetEncodingQueue_;
  dispatch_source_t dispatchSource_;
  
  BOOL watchOutputFileReady_;
  BOOL reInitializing_;
  BOOL readMetaHedaer_;
}

- (NSString *)getOutputFilePath:(NSString *)fileType;
- (id)initWithFileType:(NSString *)fileType;
- (NSString *)mediaPathForMediaType:(NSString *)mediaType;
- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(IFCapturedBufferType)mediaType;
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer
             toWriterInput:(AVAssetWriterInput *)writerInput;
- (void)saveToAlbum:(NSURL *)url;
- (void)watchOutputFile:(NSString *)filePath;
- (BOOL)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
                    ofType:(IFCapturedBufferType)mediaType
               assetWriter:(AVAssetWriter *)writer;
- (void)addMediaInput:(AVAssetWriterInput *)input
             toWriter:(AVAssetWriter *)writer;

@property (atomic, retain) NSString *fileType;

@end

@implementation IFAVAssetEncoder

static const NSInteger kMaxTempFileLength = 1024 * 1024 * 5; // max file size
NSString *const kAVAssetMP4Output = @"ifavassetout.mp4";
NSString *const kAVAssetMP4OutputWithRandom = @"ifavassetout-%05d.mp4";
const char *kAssetEncodingQueue = "com.ifactorylab.ifassetencoder.encodingqueue";

@synthesize audioEncoder = audioEncoder_;
@synthesize videoEncoder = videoEncoder_;
@synthesize assetWriter;
@synthesize assetMetaWriter;
@synthesize outputURL;
@synthesize outputFileHandle;
@synthesize captureHandler;
@synthesize progressHandler;
@synthesize maxFileSize;
@synthesize fileType;

+ (IFAVAssetEncoder *)mpeg4BaseEncoder {
  return [[IFAVAssetEncoder alloc] initWithFileType:AVFileTypeMPEG4];
}

+ (IFAVAssetEncoder *)quickTimeMovieBaseEncoder {
  return [[IFAVAssetEncoder alloc] initWithFileType:AVFileTypeQuickTimeMovie];
}

- (id)initWithFileType:(NSString *)aFileType {
  self = [super init];
  if (self != nil) {
    watchOutputFileReady_ = NO;
    maxFileSize = 0;
    firstPts_ = -1;
    readMetaHedaer_ = NO;
    self.fileType = aFileType;
    reInitializing_ = NO;
    mp4Reader_ = [[MP4Reader alloc] init];
    timeStamps_ = [[NSMutableArray alloc] initWithCapacity:10];
    
    // Generate temporary file path to store encoded file
    self.outputURL = [NSURL fileURLWithPath:[self getOutputFilePath:fileType]
                                isDirectory:NO];
    
    // Create serila queue for encoding given buffer
    assetEncodingQueue_ =
        dispatch_queue_create(kAssetEncodingQueue, DISPATCH_QUEUE_SERIAL);
    
    NSError *error = nil;
    self.assetWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                                 fileType:fileType
                                                    error:&error];
    
    NSURL *metaFile = [NSURL fileURLWithPath:[self getOutputFilePath:fileType]
                                 isDirectory:NO];
    
    // We need to write one complete file to get 'moov' mp4 meta header
    self.assetMetaWriter = [[AVAssetWriter alloc] initWithURL:metaFile
                                                     fileType:fileType
                                                        error:&error];
    if (error) {
      NSLog(@"Failed to create assetWriter - %@, %@",
            [error localizedDescription], [error userInfo]);
    }
  }
  return self;
}

- (void)addMediaInput:(AVAssetWriterInput *)input
             toWriter:(AVAssetWriter *)writer {
  if (writer && input && [writer canAddInput:input]) {
    @try {
      [writer addInput:input];
    } @catch (NSException *exception) {
      NSLog(@"Couldn't add input: %@", [exception description]);
    }
  }
}

- (void)setVideoEncoder:(IFVideoEncoder *)videoEncoder {
  // [self addMediaInput:videoEncoder.assetWriterInput toWriter:assetMetaWriter];
  [self addMediaInput:videoEncoder.assetWriterInput toWriter:assetWriter];
  videoEncoder_ = [videoEncoder retain];
}

- (void)setAudioEncoder:(IFAudioEncoder *)audioEncoder {
  // [self addMediaInput:audioEncoder_.assetWriterInput toWriter:assetMetaWriter];
  [self addMediaInput:audioEncoder_.assetWriterInput toWriter:assetWriter];
  audioEncoder_ = [audioEncoder retain];
}

- (NSString *)getOutputFilePath:(NSString *)fileType {
  // NSString *path = [self mediaPathForMediaType:@"videos"];
  NSString *path = NSTemporaryDirectory();
  NSString *filePath =  [path stringByAppendingPathComponent:
          [NSString stringWithFormat:kAVAssetMP4OutputWithRandom, rand() % 99999]];
  [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
  return filePath;
}

- (NSString *)mediaPathForMediaType:(NSString *)mediaType {
  NSArray *paths =
      NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                          NSUserDomainMask, YES);
  NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
  NSString *suffix = mediaType;
  return [basePath stringByAppendingPathComponent:suffix];
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer
             toWriterInput:(AVAssetWriterInput *)writerInput {
  if (writerInput.readyForMoreMediaData) {
    @try {
      if (![writerInput appendSampleBuffer:sampleBuffer]) {
        NSLog(@"Failed to append sample buffer: %@", [assetWriter error]);
      }
    } @catch (NSException *exception) {
      NSLog(@"Couldn't append sample buffer: %@", [exception description]);
    }
  }
}

- (BOOL)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
                    ofType:(IFCapturedBufferType)mediaType
               assetWriter:(AVAssetWriter *)writer {
  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return NO;
  }
  
  if (writer.status == AVAssetWriterStatusUnknown) {
    if ([writer startWriting]) {
      @try {
        [writer
         startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
      }
      @catch (NSException *exception) {
        NSLog(@"Couldn't add audio input: %@", [exception description]);
        return NO;
      }
		} else {
			NSLog(@"Failed to start writing(%@): %@", writer.outputURL,
            [writer error]);
      return NO;
		}
	}
  
  if (writer.status == AVAssetWriterStatusWriting) {
    AVAssetWriterInput *input = nil;
    if (mediaType == kBufferVideo) {
      input = videoEncoder_.assetWriterInput;
    } else if (mediaType == kBufferAudio) {
      input = audioEncoder_.assetWriterInput;

    }
    
    if (input != nil) {
      [self appendSampleBuffer:sampleBuffer toWriterInput:input];
    }
  }

  return YES;
}

- (void)handleMetaData {
  NSData *movWithMoov =
      [NSData dataWithContentsOfFile:assetMetaWriter.outputURL.path];
  NSLog(@"%@", [movWithMoov hexString]);
  
  // Let's parse mp4 header
  MP4Reader *mp4Reader = [[MP4Reader alloc] init];
  [mp4Reader readData:movWithMoov];
  
  // if (!watchOutputFileReady_) {
  [self watchOutputFile:[outputURL path]];
  // }
}

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(IFCapturedBufferType)mediaType {
  
  // @synchronized (self) {
    if (!readMetaHedaer_) {
      // If we don't finish writing in AVAssetWriter, we never get 'moov' section
      // for parsing mp4 file.
      readMetaHedaer_ = YES;
      
      /*
      if ([self encodeSampleBuffer:sampleBuffer
                            ofType:mediaType
                       assetWriter:assetMetaWriter]) {
        // We finish encoding here for meta data
        [assetMetaWriter finishWritingWithCompletionHandler:^{
          [self handleMetaData];
        }];
      }
       */
    } 
  // }
  
  CMTime prestime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  double dPTS = (double)(prestime.value) / prestime.timescale;
  NSNumber* pts = [NSNumber numberWithDouble:dPTS];
  @synchronized (timeStamps_) {
    [timeStamps_ addObject:pts];
  }
  
  if ([self encodeSampleBuffer:sampleBuffer
                        ofType:mediaType
                   assetWriter:assetWriter]) {
    if (!watchOutputFileReady_) {
      watchOutputFileReady_ = YES;
      [self watchOutputFile:[outputURL path]];
    }
  }
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
                    ofType:(IFCapturedBufferType)mediaType {
  if (mediaType == kBufferAudio) {
    // If audio encoder is not ready to write, we need to setup it up with
    // CMFormatDescriptionRef
    if (audioEncoder_.assetWriterInput == nil) {
      CMFormatDescriptionRef formatDescription =
          CMSampleBufferGetFormatDescription(sampleBuffer);
      [audioEncoder_ setupWithFormatDescription:formatDescription];
/*
      if (assetMetaWriter && [assetMetaWriter canAddInput:self.audioEncoder.assetWriterInput]) {
        @try {
          [assetMetaWriter addInput:audioEncoder_.assetWriterInput];
        } @catch (NSException *exception) {
          NSLog(@"Couldn't add audio input: %@", [exception description]);
        }
      }
  */
      if (assetWriter && [assetWriter canAddInput:self.audioEncoder.assetWriterInput]) {
        @try {
          [assetWriter addInput:audioEncoder_.assetWriterInput];
        } @catch (NSException *exception) {
          NSLog(@"Couldn't add audio input: %@", [exception description]);
        }
      }
    }
  }
  
  CFRetain(sampleBuffer);
  
  // We'd like encoding job running asynchronously
  dispatch_async(assetEncodingQueue_, ^{
    // Write the given sample buffer to output file through AVAssetWriter
    [self writeSampleBuffer:sampleBuffer ofType:mediaType];
    CFRelease(sampleBuffer);
  });
}

- (void)saveToAlbum:(NSURL *)url {
  ALAssetsLibrary *assetsLibrary = [[[ALAssetsLibrary alloc] init] autorelease];
  if ([assetsLibrary videoAtPathIsCompatibleWithSavedPhotosAlbum:url]) {
    [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:url
                                      completionBlock:^(NSURL *assetURL, NSError *error) {
                                      }];
  }
}

- (void)stopWithSaveToAlbum:(BOOL)saveToAlbum {
  if (assetWriter.status == AVAssetWriterStatusWriting) {
    @try {
      [self.audioEncoder.assetWriterInput markAsFinished];
      [self.videoEncoder.assetWriterInput markAsFinished];
      [assetWriter finishWritingWithCompletionHandler:^{
        if (assetWriter.status == AVAssetWriterStatusFailed) {
          NSLog(@"Failed to finish writing: %@", [assetWriter error]);
        } else {
          // Send over last encoded chunk to the buffer handler.
          // [self uploadLocalURL:assetWriter.outputURL];
          if (saveToAlbum) {
            [self saveToAlbum:outputURL];
          }
        }
      }];
    } @catch (NSException *exception) {
      NSLog(@"Caught exception: %@", [exception description]);
    }
  } else {
    if (saveToAlbum) {
      [self saveToAlbum:outputURL];
    }
  }
  
  if (dispatchSource_) {
    dispatch_source_cancel(dispatchSource_);
    dispatchSource_ = NULL;
  }
  
  if (assetEncodingQueue_ != nil) {
    assetEncodingQueue_ = nil;
  }
}

- (void)watchOutputFile:(NSString *)filePath {
  dispatch_queue_t queue =
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  // int file = open([filePath UTF8String], O_EVTONLY);
  self.outputFileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
  
  dispatchSource_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,
                                           [outputFileHandle fileDescriptor],
                                           DISPATCH_VNODE_DELETE |
                                           DISPATCH_VNODE_WRITE |
                                           DISPATCH_VNODE_EXTEND |
                                           DISPATCH_VNODE_ATTRIB |
                                           DISPATCH_VNODE_LINK |
                                           DISPATCH_VNODE_RENAME |
                                           DISPATCH_VNODE_REVOKE,
                                           queue);
  dispatch_source_set_event_handler(dispatchSource_, ^{
    // Read data flags from the created source
    unsigned long flags = dispatch_source_get_data(dispatchSource_);
    // If the file has deleted, cancel current watching job.
    if (flags & DISPATCH_VNODE_DELETE) {
      dispatch_source_cancel(dispatchSource_);
    }
    
    // When file size has changed,
    if (flags & DISPATCH_VNODE_EXTEND) {
      NSData *chunk = [outputFileHandle readDataToEndOfFile];
      if ([chunk length] > 0) {
        // NSLog(@"Actual data\n%@", [chunk hexString]);
        if (captureHandler) {
          double pts = 0;
          @synchronized (timeStamps_) {
            if ([timeStamps_ count] > 0) {
              pts = [timeStamps_[0] doubleValue];
              [timeStamps_ removeObjectAtIndex:0];
              if (firstPts_ < 0) {
                firstPts_ = pts;
              }
            } else {
              NSLog(@"no pts for buffer");
            }
          }

          NSArray *frames = [mp4Reader_ readFrame:chunk];
          captureHandler(frames, chunk, pts);
        }
      }
      
      if (self.maxFileSize > 0) {
        NSDictionary *attr =
          [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
      
        @synchronized(self) {
          if (reInitializing_) {
            // store incoming buffer in the queue
            return;
          }
        }

        if (maxFileSize <= [attr fileSize]) {
          NSLog(@"total file size %lld, max %lld", [attr fileSize], self.maxFileSize);
        
          @synchronized(self) {
            reInitializing_ = YES;
          }
          
          // Finish current encoding
          // Release all resources related AVAssetWriter
          if (assetWriter.status == AVAssetWriterStatusWriting) {
            @try {
              @synchronized (self) {
                [self.audioEncoder.assetWriterInput markAsFinished];
                [self.videoEncoder.assetWriterInput markAsFinished];
              }
              
              // Wait until it finishes
              [assetWriter finishWritingWithCompletionHandler:^{
                if (assetWriter.status == AVAssetWriterStatusFailed) {
                  NSLog(@"Failed to finish writing: %@", [assetWriter error]);
                } else {
                  if (progressHandler) {
                    progressHandler(filePath);
                  }
                }
                
                // Regardless of job failure, we need to reset current encoder
                dispatch_source_cancel(dispatchSource_);
              
                // Once it's done, generate new file name and reinitiate AVAssetWrite
                outputURL = [NSURL fileURLWithPath:[self getOutputFilePath:fileType]
                                       isDirectory:NO];

                [assetWriter release];
                NSError *error;
                assetWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                                        fileType:fileType
                                                           error:&error];
                
                // setVideoEncoder and setAudioEncoder will retain the given
                // encoder objects so we need to reduce reference as it's retained
                // in the functions.
                [assetWriter addInput:videoEncoder_.assetWriterInput];
                [assetWriter addInput:audioEncoder_.assetWriterInput];
                
                // we are good to go.
                @synchronized (self) {
                  reInitializing_ = NO;  
                }
                
                watchOutputFileReady_ = NO;
              }];
            } @catch (NSException *exception) {
              NSLog(@"Caught exception: %@", [exception description]);
            }
          }
        }
      }      
    }
  });
  
  dispatch_source_set_cancel_handler(dispatchSource_, ^(void){
    [outputFileHandle closeFile];
  });
  
	dispatch_resume(dispatchSource_);
  watchOutputFileReady_ = YES;
}

- (void)dealloc {
  [timeStamps_ release];
  [mp4Reader_ release];
  
  if (self.audioEncoder) {
    [self.audioEncoder release];
  }
  
  if (self.videoEncoder) {
    [self.videoEncoder release];
  }
  
  if (assetWriter) {
    [assetWriter release];
  }
  
  if (assetMetaWriter) {
    [assetMetaWriter release];
  }
  
  if (outputURL) {
    [outputURL release];
  }
  [super dealloc];
}

@end
