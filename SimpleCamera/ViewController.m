//
//  ViewController.m
//  SimpleCamera
//
//  Created by Roman Osadchuk on 19.06.16.
//  Copyright © 2016 Roman Osadchuk. All rights reserved.
//

#import "ViewController.h"

#import "ORPreviewVIew.h"
#import "ORCaptureProcessor.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *stillButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraButton;

@property (strong, nonatomic) UIColor *redColor;
@property (strong, nonatomic) UIColor *defaultColor;

@property (weak, nonatomic) IBOutlet ORPreviewView *capturePreviewView;

@property (strong, nonatomic) ORCaptureProcessor *captureProcessor;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.captureProcessor = [[ORCaptureProcessor alloc] initWithPreviewView:self.capturePreviewView];
    self.captureProcessor.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.defaultColor = self.recordButton.backgroundColor;
    self.redColor = [UIColor redColor];
    
    [self.captureProcessor startRunning];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self.captureProcessor stopRunning];
}

#pragma mark - Actions

- (IBAction)handleRecordButtonTapped:(id)sender
{
    [self.captureProcessor recordMovieToFile:nil];
    self.recordButton.backgroundColor = self.redColor;
}

- (IBAction)handleStillButtonTapped:(id)sender
{
    [self.captureProcessor snapStillImage];
    
    self.capturePreviewView.layer.opacity = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.capturePreviewView.layer.opacity = 1.0;
    }];
}

- (IBAction)handleCameraButtonTapped:(id)sender
{
    [self.captureProcessor changeCamera];
}

#pragma mark - ORCaptureProcessorDelegate

- (void)captureProcessorCameraSetupResult:(ORCaptureSetupResult)cameraSetupResult
{
    
}

- (void)captureProcessorAudioSetupResult:(ORCaptureSetupResult)audioSetupResult
{
    
}

- (void)captureProcessorPhotoLibraryWithPermissionResult:(BOOL)permissionResultAuthorized
{
    
}

- (void)captureProcessor:(ORCaptureProcessor *)captureProcessor capturedStillImage:(UIImage *)image
{
    
}

- (void)captureProcessor:(ORCaptureProcessor *)captureProcessor finishedRecordingToFile:(NSURL *)fileURL
{
    self.recordButton.backgroundColor = self.defaultColor;
}

#pragma mark - Orientation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    BOOL satisfiedPositions = UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation);
    
    if (satisfiedPositions) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.capturePreviewView.layer;
        previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
    }
}

@end
