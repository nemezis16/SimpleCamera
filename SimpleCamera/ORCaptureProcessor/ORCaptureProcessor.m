//
//  ORCaptureProcessor.m
//  SimpleCamera
//
//  Created by Roman Osadchuk on 20.06.16.
//  Copyright © 2016 Roman Osadchuk. All rights reserved.
//

#import "ORCaptureProcessor.h"

@import Photos;

static void * SessionRunningContext = &SessionRunningContext;
static void * CapturingStillImageContext = &CapturingStillImageContext;

static NSString *const SessionRunningKeyPath = @"running";
static NSString *const CapturingStillImageKeyPath = @"capturingStillImage";

@interface ORCaptureProcessor () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t sessionQueue;

@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@property (assign, nonatomic) ORCaptureSetupResult cameraSetupResult;
@property (assign, nonatomic) ORCaptureSetupResult audioSetupResult;

@property (strong, nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;

@property (strong, nonatomic) NSDate *startCapturingDate;

@property (assign, nonatomic, getter = isSessionRunning) BOOL sessionRunning;

@end

@implementation ORCaptureProcessor

#pragma mark - Initializers
#pragma mark

- (instancetype)initWithPreviewView:(ORPreviewView *)previewView
{
    if (self = [super init]) {
        _previewView = previewView;
        _previewView.session = [[AVCaptureSession alloc] init];
        _sessionQueue = dispatch_queue_create("capture_session_queue", DISPATCH_QUEUE_SERIAL);
        
        [self accessCamera];
        [self accessAudio];
        [self setupCapture];
    }
    return self;
}

-(void)dealloc
{
    [self stopRunning];
}

#pragma mark - Accessors

- (BOOL)isRecording
{
    return self.movieFileOutput.isRecording;
}

#pragma mark - Public
#pragma mark

- (void)startRunning
{
    [self performCameraSetupResultMethodDelegate];
    [self performAudioSetupResultMethodDelegate];
    
    if (self.cameraSetupResult == ORCaptureSetupResultAuthorized) {
        dispatch_async(self.sessionQueue, ^{
            [self addObservers];
            [self.previewView.session startRunning];
            self.sessionRunning = self.previewView.session.isRunning;
        });
    }
}

- (void)stopRunning
{
    if (self.cameraSetupResult == ORCaptureSetupResultAuthorized ) {
        dispatch_async(self.sessionQueue, ^{
            [self.previewView.session stopRunning];
            [self removeObservers];
        });
    }
}

- (void)snapStillImage
{
    dispatch_async(self.sessionQueue, ^{
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
        
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        connection.videoOrientation = previewLayer.connection.videoOrientation;
        
        [ORCaptureProcessor setFlashMode:AVCaptureFlashModeAuto forDevice:self.videoDeviceInput.device];
        
        __weak typeof(self) weakSelf = self;
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            if (imageDataSampleBuffer) {
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                
                [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                    BOOL authorized;
                    if (status == PHAuthorizationStatusAuthorized) {
                        authorized = YES;
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            if ([PHAssetCreationRequest class]) {
                                [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
                            } else {
                                NSLog(@"Error. Can't save image. PHAssetCreationRequest supporting only from iOS 9");
                            }
                        } completionHandler:^(BOOL success, NSError * _Nullable error) {
                            if (success) {
                                [weakSelf performCapturedStillImageMethodDelegateWithImage:[UIImage imageWithData:imageData]];
                            } else {
                                NSLog(@"Error occurred while saving image to photo library: %@", error);
                            }
                        }];
                    }
                    [weakSelf performPhotoLibraryPermissionMethodDelegateWithPermission:authorized];
                }];
            } else {
                NSLog( @"Could not capture still image: %@", error );
            }
        }];
    });
}

- (void)recordMovieToFile:(NSURL *)fileURL
{
    dispatch_async(self.sessionQueue, ^{
        if (!self.movieFileOutput.isRecording) {
            if ([UIDevice currentDevice].isMultitaskingSupported) {
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            }
            self.startCapturingDate = [NSDate date];
            
            AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
            AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            connection.videoOrientation = previewLayer.connection.videoOrientation;
            [ORCaptureProcessor setFlashMode:AVCaptureFlashModeOff forDevice:self.videoDeviceInput.device];
            
            NSURL *outputFileURL = fileURL ?: [self defaultFileURL];

            [self.movieFileOutput startRecordingToOutputFileURL:outputFileURL recordingDelegate:self];
        } else {
            [self.movieFileOutput stopRecording];
        }
    });
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    dispatch_block_t cleanup = ^{
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        if (currentBackgroundRecordingID != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
        }
    };
    
    BOOL success = YES;
    
    if (error) {
        NSLog(@"Movie file finishing error: %@", error);
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if (success) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges: ^{
                    if ([PHAssetResourceCreationOptions class]) {
                        PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
                        options.shouldMoveFile = YES;
                        PHAssetCreationRequest *changeRequest = [PHAssetCreationRequest creationRequestForAsset];
                        [changeRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
                        
                        [self performFinishingRecordingToFileMethodDelegateWithURL:outputFileURL];
                    } else {
                        NSLog(@"Error. Can't save video. PHAssetCreationRequest supporting only from iOS 9");
                    }
                } completionHandler:^(BOOL success, NSError *error) {
                    if (!success) {
                        NSLog( @"Could not save movie to photo library: %@", error );
                    }
                    cleanup();
                }];
            } else {
                cleanup();
            }
        }];
    } else {
        cleanup();
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMTime currentTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
#warning todo
}

#pragma mark - Private

#pragma mark - Access

- (void)accessCamera
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusNotDetermined: {
            dispatch_suspend(self.sessionQueue);
            
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                self.cameraSetupResult = granted ?  ORCaptureSetupResultAuthorized : ORCaptureSetupResultNotAuthorized;
                [self startRunning];
                dispatch_resume(self.sessionQueue);
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            self.cameraSetupResult = ORCaptureSetupResultAuthorized;
            break;
        }
        default: {
            dispatch_suspend(self.sessionQueue);
            self.cameraSetupResult = ORCaptureSetupResultNotAuthorized;
            break;
        }
    }
}

- (void)accessAudio
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
        case AVAuthorizationStatusNotDetermined: {
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                self.audioSetupResult = granted ?  ORCaptureSetupResultAuthorized : ORCaptureSetupResultNotAuthorized;
                [self performAudioSetupResultMethodDelegate];
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            self.audioSetupResult = ORCaptureSetupResultAuthorized;
            break;
        }
        default: {
            self.audioSetupResult = ORCaptureSetupResultNotAuthorized;
            break;
        }
    }
}

#pragma mark - Setup

#pragma mark SetupCapture

- (void)setupCapture
{
    dispatch_async(self.sessionQueue, ^{
        if (self.cameraSetupResult != ORCaptureSetupResultAuthorized) {
            return;
        }
        self.backgroundRecordingID = UIBackgroundTaskInvalid;
        
        [self.previewView.session beginConfiguration];
        
        [self setupDeviceInputs];
        [self setupCaptureOutputs];
        [self setupVideoOrientation];
        
        [self.previewView.session commitConfiguration];
    });
}

#pragma mark SetupInputs

- (void)setupDeviceInputs
{
    AVCaptureSession *session = self.previewView.session;
    
    AVCaptureDeviceInput *videoDeviceInput = [self defaultVideoDeviceInput];
    if ([session canAddInput:videoDeviceInput]) {
        [session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
    } else {
        NSLog(@"Could not add video device input to the session");
        self.cameraSetupResult = ORCaptureSetupResultSessionConfigurationFailed;
    }
    
    AVCaptureDeviceInput *audioDeviceInput = [self defaultAudioDeviceInput];
    if ([session canAddInput:audioDeviceInput]) {
        [session addInput:audioDeviceInput];
    } else {
        NSLog(@"Could not add audio device input to the session");
        self.audioSetupResult = ORCaptureSetupResultSessionConfigurationFailed;
    }
}

- (AVCaptureDeviceInput *)defaultVideoDeviceInput
{
    NSError *error;
    AVCaptureDevice *videoDevice = [ORCaptureProcessor deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (!videoDeviceInput) {
        NSLog(@"Could not create video device input: %@", error);
    }
    
    return videoDeviceInput;
}

- (AVCaptureDeviceInput *)defaultAudioDeviceInput
{
    NSError *error;
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if (!audioDeviceInput) {
        NSLog(@"Could not create audio device input: %@", error);
    }
    
    return audioDeviceInput;
}

#pragma mark SetupOutputs

- (void)setupCaptureOutputs
{
    AVCaptureSession *session = self.previewView.session;
    
    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    
    if ([session canAddOutput:movieFileOutput]) {
        [session addOutput:movieFileOutput];
        AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection.isVideoStabilizationSupported) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        self.movieFileOutput = movieFileOutput;
    } else {
        NSLog(@"Could not add movie file output to the session");
        self.cameraSetupResult = ORCaptureSetupResultSessionConfigurationFailed;
    }
    
    AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    if ([session canAddOutput:stillImageOutput]) {
        stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
        [session addOutput:stillImageOutput];
        self.stillImageOutput = stillImageOutput;
    } else {
        NSLog(@"Could not add still image output to the session");
        self.cameraSetupResult = ORCaptureSetupResultSessionConfigurationFailed;
    }
}

#pragma mark DefaultVideoDirectory

- (NSURL *)defaultFileURL
{
    NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
    
    return [NSURL fileURLWithPath:outputFilePath];
}

#pragma mark - Device Configuration

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if(device.flashMode && [device isFlashModeSupported:flashMode]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        } else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

#pragma mark - VideoOrientation

- (void)setupVideoOrientation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        previewLayer.connection.videoOrientation = [self currentVideoOrientation];
    });
}

- (AVCaptureVideoOrientation)currentVideoOrientation
{
    UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
    AVCaptureVideoOrientation currentVideoOrientation = AVCaptureVideoOrientationPortrait;
    if (statusBarOrientation != UIInterfaceOrientationUnknown) {
        currentVideoOrientation = (AVCaptureVideoOrientation) statusBarOrientation;
    }
    
    return currentVideoOrientation;
}

#pragma mark - KVO and Notifications

- (void)addObservers
{
    AVCaptureSession *session = self.previewView.session;
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:session];
    [notificationCenter addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:session];
    [notificationCenter addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:session];
    
    [session addObserver:self forKeyPath:SessionRunningKeyPath options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self.stillImageOutput addObserver:self forKeyPath:CapturingStillImageKeyPath options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)context:CapturingStillImageContext];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    @try {
        [self.previewView.session removeObserver:self forKeyPath:SessionRunningKeyPath context:SessionRunningContext];
        [self.stillImageOutput removeObserver:self forKeyPath:CapturingStillImageKeyPath context:CapturingStillImageContext];
    } @catch (NSException *exception) {
        NSLog(@"%@", exception.description);
    }
}

#pragma mark KeyValueObserve

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if (context == SessionRunningContext) {
       
    } else if (context == CapturingStillImageContext) {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        if (isCapturingStillImage) {
#warning to delete later 
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark NotificationEvents

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    
}

#pragma mark - PerformDelegateMethods

- (void)performCameraSetupResultMethodDelegate
{
    if (self.cameraSetupResult && self.delegate && [self.delegate respondsToSelector:@selector(captureProcessorCameraSetupResult:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate captureProcessorCameraSetupResult:self.cameraSetupResult];
        });
    }
}

- (void)performAudioSetupResultMethodDelegate
{
    if (self.audioSetupResult && self.delegate && [self.delegate respondsToSelector:@selector(captureProcessorAudioSetupResult:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate captureProcessorAudioSetupResult:self.audioSetupResult];
        });
    }
}

- (void)performPhotoLibraryPermissionMethodDelegateWithPermission:(BOOL)permissionAuthorized
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureProcessorPhotoLibraryWithPermissionResult:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
             [self.delegate captureProcessorPhotoLibraryWithPermissionResult:permissionAuthorized];
        });
    }
}

- (void)performCapturedStillImageMethodDelegateWithImage:(UIImage *)image
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureProcessor:capturedStillImage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate captureProcessor:self capturedStillImage:image];
        });
    }
}

- (void)performFinishingRecordingToFileMethodDelegateWithURL:(NSURL *)fileURL
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureProcessor:finishedRecordingToFile:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate captureProcessor:self finishedRecordingToFile:fileURL];
        });
    }
}

@end
