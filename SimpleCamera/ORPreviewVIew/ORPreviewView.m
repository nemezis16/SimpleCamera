//
//  ORPreviewView.m
//  SimpleCamera
//
//  Created by Roman Osadchuk on 01.07.16.
//  Copyright © 2016 Roman Osadchuk. All rights reserved.
//

@import AVFoundation;

#import "ORPreviewView.h"

@implementation ORPreviewView

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session
{
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    return previewLayer.session;
}

- (void)setSession:(AVCaptureSession *)session
{
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    previewLayer.session = session;
}

@end
