//
//  ORCaptureProcessor.h
//  SimpleCamera
//
//  Created by Roman Osadchuk on 20.06.16.
//  Copyright © 2016 Roman Osadchuk. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "ORPreviewView.h"

@class ORCaptureProcessor;

typedef NS_ENUM(NSInteger, ORCaptureSetupResult) {
    ORCaptureSetupResultNotDetermined = 0,
    ORCaptureSetupResultAuthorized,
    ORCaptureSetupResultNotAuthorized,
    ORCaptureSetupResultSessionConfigurationFailed
};

@protocol ORCaptureProcessorDelegate <NSObject>

@optional

#pragma mark CaptureSetupResults

- (void)captureProcessorCameraSetupResult:(ORCaptureSetupResult)cameraSetupResult;

- (void)captureProcessorAudioSetupResult:(ORCaptureSetupResult)audioSetupResult;

- (void)captureProcessorPhotoLibraryWithPermissionResult:(BOOL)permissionResultAuthorized;

#pragma mark CaptureEvents

- (void)captureProcessor:(ORCaptureProcessor *)captureProcessor capturedStillImage:(UIImage *)image;

- (void)captureProcessor:(ORCaptureProcessor *)captureProcessor finishedRecordingToFile:(NSURL *)fileURL;

- (void)captureProcessor:(ORCaptureProcessor *)captureProcessor recordedForTime:(CGFloat)seconds;

@end

@interface ORCaptureProcessor : NSObject
      
@property (strong, nonatomic) ORPreviewView *previewView;

@property (assign, nonatomic) BOOL isRecording;

@property (weak, nonatomic) id <ORCaptureProcessorDelegate> delegate;

- (instancetype)initWithPreviewView:(ORPreviewView *)previewView;

- (void)startRunning;
- (void)stopRunning;

//if fileURL == nil then record directly to gallery
- (void)recordMovieToFile:(NSURL *)fileURL;
- (void)snapStillImage;

@end
