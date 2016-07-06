//
//  ORPreviewView.h
//  SimpleCamera
//
//  Created by Roman Osadchuk on 01.07.16.
//  Copyright © 2016 Roman Osadchuk. All rights reserved.
//

@import UIKit;

@class AVCaptureSession;

@interface ORPreviewView : UIView

@property (nonatomic) AVCaptureSession *session;

@end
