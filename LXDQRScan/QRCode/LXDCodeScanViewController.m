//
//  LXDCodeScanViewController.m
//  KamoClient
//
//  Created by linxinda on 2017/2/14.
//  Copyright © 2017年 Jolimark. All rights reserved.
//

#import "LXDCodeScanViewController.h"
#import <AVFoundation/AVFoundation.h>


#ifndef kScreenWidth
#define kScreenWidth CGRectGetWidth([UIScreen mainScreen].bounds)
#endif
#ifndef kScreenHeight
#define kScreenHeight CGRectGetHeight([UIScreen mainScreen].bounds)
#endif
#define LXDCodeScanSpacing 50


static inline UIImage * kImageNamed(NSString * imageName) {
    NSUInteger scale = [UIScreen mainScreen].scale;
    NSString * realImageName = [NSString stringWithFormat: @"%@@%lux.png", imageName, scale];
    return [UIImage imageWithContentsOfFile: [[NSBundle mainBundle] pathForResource: realImageName ofType: nil]];
}


@interface LXDCodeScanViewController ()<AVCaptureMetadataOutputObjectsDelegate, UINavigationControllerDelegate,  UIImagePickerControllerDelegate>

/// 扫描线条
@property (nonatomic, strong) UIImageView * scanLine;
/// 方形扫描框
@property (nonatomic, strong) UIImageView * scanFrame;
/// block回调
@property (nonatomic, copy) void (^complete)(LXDCodeScanViewController * scanVC, NSString * codeInfo);

/// 相机权限
@property (nonatomic, assign) AVAuthorizationStatus didAuthorization;
/// 视频会话
@property (nonatomic, strong) AVCaptureSession * session;
/// 音频输入设备（摄像头）
@property (nonatomic, strong) AVCaptureDeviceInput * input;
/// 音频二进制数据输出对象
@property (nonatomic, strong) AVCaptureMetadataOutput * output;
/// 视频视频图层（将二进制转成图像）
@property (nonatomic, strong) AVCaptureVideoPreviewLayer * scanView;

@end

@implementation LXDCodeScanViewController


#pragma mark - View Life
- (instancetype)initWithComplete: (void(^)(LXDCodeScanViewController * scanVC, NSString * codeInfo))complete {
    if (self = [super init]) {
        self.complete = complete;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)viewWillAppear: (BOOL)animated {
    [super viewWillAppear: animated];
    [self.navigationController setNavigationBarHidden: YES animated: animated];
    if (!_didAuthorization) { return; }
    [self startScanning];
}

- (void)viewWillDisappear: (BOOL)animated {
    [super viewWillDisappear: animated];
    [self.navigationController setNavigationBarHidden: NO animated: animated];
    if (!_didAuthorization) { return; }
    [self stopScanning];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


#pragma mark - Private
/// 开始扫描
- (void)startScanning {
    [self.session startRunning];
    [self.scanLine.layer addAnimation: [self moveAnimation] forKey: nil];
}

/// 停止扫描
- (void)stopScanning {
    [self.session stopRunning];
    [self.scanLine.layer removeAllAnimations];
}

/// 扫描框动画
- (CAAnimation *)moveAnimation {
    const CGFloat scanSize = kScreenWidth - LXDCodeScanSpacing * 2;
    CABasicAnimation * move = [CABasicAnimation animationWithKeyPath: @"position"];
    move.fromValue = [NSValue valueWithCGPoint: self.scanLine.center];
    move.toValue = [NSValue valueWithCGPoint: CGPointMake(scanSize / 2, scanSize / 2)];
    move.repeatCount = CGFLOAT_MAX;
    move.removedOnCompletion = NO;
    move.duration = 1.5;
    return move;
}

/// 弹窗警告
- (void)alertWithTitle: (NSString *)title message: (NSString *)message {
    UIAlertController * alert = [UIAlertController alertControllerWithTitle: title message: message preferredStyle: UIAlertControllerStyleAlert];
    [alert addAction: [UIAlertAction actionWithTitle: @"确定" style: UIAlertActionStyleCancel handler: nil]];
    [self presentViewController: alert animated: YES completion: nil];
}


#pragma mark - Event
/// 开关闪光灯
- (void)switchFlash: (UIButton *)item {
    [item setSelected: !item.selected];
    AVCaptureDevice * device = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
    if ([device hasTorch] && [device hasFlash]){
        [device lockForConfiguration: nil];
        if (item.isSelected) {
            [device setTorchMode: AVCaptureTorchModeOn];
            [device setFlashMode: AVCaptureFlashModeOn];
        } else {
            [device setTorchMode: AVCaptureTorchModeOff];
            [device setFlashMode: AVCaptureFlashModeOff];
        }
        [device unlockForConfiguration];
    }
}

/// 打开相册
- (void)openPhotoLibrary {
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypePhotoLibrary]) {
        UIImagePickerController * imagePicker = [UIImagePickerController new];
        imagePicker.delegate = self;
        imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        imagePicker.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
        [self presentViewController: imagePicker animated: YES completion: nil];
    } else {
        [self alertWithTitle: @"提示" message: @"设备不支持访问相册，请在设置->隐私->照片中进行设置！"];
    }
}

/// 返回
- (void)back {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated: YES];
    } else {
        [self dismissViewControllerAnimated: YES completion: nil];
    }
}


#pragma mark - Setup
/// UI构建
- (void)setupUI {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType: AVMediaTypeVideo];
    self.didAuthorization = (status == AVAuthorizationStatusAuthorized || status == AVAuthorizationStatusNotDetermined);
    
    if (self.didAuthorization) {
        [self.view.layer addSublayer: self.scanView];
    }
    const CGFloat scanSize = kScreenWidth - LXDCodeScanSpacing * 2;
    CGRect scanFrame = CGRectMake(LXDCodeScanSpacing, (kScreenHeight - scanSize) / 2, scanSize, scanSize);
    UIBezierPath * maskPath = [UIBezierPath bezierPathWithRect: CGRectMake(0, 0, kScreenWidth, kScreenHeight)];
    [maskPath appendPath: [UIBezierPath bezierPathWithRect: scanFrame]];
    
    CAShapeLayer * maskLayer = [CAShapeLayer layer];
    maskLayer.fillColor = [UIColor colorWithWhite: .1 alpha: .6].CGColor;
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    maskLayer.path = maskPath.CGPath;
    [self.view.layer addSublayer: maskLayer];
    
    UIView * scanContent = [[UIView alloc] initWithFrame: scanFrame];
    scanContent.backgroundColor = [UIColor clearColor];
    scanContent.clipsToBounds = YES;
    self.scanFrame = [[UIImageView alloc] initWithFrame: scanContent.bounds];
    self.scanFrame.image = kImageNamed(@"scan_frame");
    [scanContent addSubview: self.scanFrame];
    
    self.scanLine = [[UIImageView alloc] initWithFrame: CGRectMake(0, -scanSize, scanSize, scanSize)];
    self.scanLine.image = kImageNamed(@"scan_line");
    [scanContent addSubview: self.scanLine];
    [self.view addSubview: scanContent];
    
    UIButton *(^buttonCreator)(CGRect frame, NSString * imageName, SEL action) = ^UIButton *(CGRect frame, NSString * imageName, SEL action) {
        UIButton * item = [[UIButton alloc] initWithFrame: frame];
        [item addTarget: self action: action forControlEvents: UIControlEventTouchUpInside];
        [item setImage: kImageNamed(imageName) forState: UIControlStateNormal];
        return item;
    };
    const CGFloat itemSize = 40;
    const CGFloat y = (kScreenHeight - scanSize) / 2 - itemSize * 2;
    UIButton * photoLibrary = buttonCreator(CGRectMake(LXDCodeScanSpacing, y, itemSize, itemSize), @"scan_photo_library", @selector(openPhotoLibrary));
    UIButton * switchFlash = buttonCreator(CGRectMake((kScreenWidth - itemSize) / 2, y, itemSize, itemSize), @"scan_flash_off", @selector(switchFlash:));
    UIButton * close = buttonCreator(CGRectMake(kScreenWidth - itemSize - LXDCodeScanSpacing, y, itemSize, itemSize), @"scan_close", @selector(back));
    
    [switchFlash setImage: kImageNamed(@"scan_flash_on") forState: UIControlStateSelected];
    [self.view addSubview: photoLibrary];
    [self.view addSubview: switchFlash];
    [self.view addSubview: close];
    
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(setupInterestRect:) name: AVCaptureInputPortFormatDescriptionDidChangeNotification object: nil];
}

/// 构建视频I/O对象
- (void)setupIODevice {
    if ([self.session canAddInput: self.input]) {
        [_session addInput: _input];
    }
    if ([self.session canAddOutput: self.output]) {
        [_session addOutput: _output];
        _output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeCode128Code];
    }
}

/// 构建二维码扫描有效区域
- (void)setupInterestRect: (NSNotification *)notification {
    const CGFloat scanSize = kScreenWidth - LXDCodeScanSpacing * 2;
    CGRect scanFrame = CGRectMake(LXDCodeScanSpacing, (kScreenHeight - scanSize) / 2, scanSize, scanSize);
    self.output.rectOfInterest = [self.scanView metadataOutputRectOfInterestForRect: scanFrame];
}


#pragma mark - Lazy Load
- (AVCaptureSession *)session {
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
        [_session setSessionPreset: AVCaptureSessionPresetHigh];    //高质量采集
        [self setupIODevice];
    }
    return _session;
}

- (AVCaptureDeviceInput *)input {
    if (!_input) {
        AVCaptureDevice * device = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
        _input = [AVCaptureDeviceInput deviceInputWithDevice: device error: nil];
    }
    return _input;
}

- (AVCaptureMetadataOutput *)output {
    if (!_output) {
        _output = [AVCaptureMetadataOutput new];
        [_output setMetadataObjectsDelegate: self queue: dispatch_get_main_queue()];
    }
    return _output;
}

- (AVCaptureVideoPreviewLayer *)scanView {
    if (!_scanView) {
        _scanView = [AVCaptureVideoPreviewLayer layerWithSession: self.session];
        _scanView.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _scanView.frame = self.view.bounds;
    }
    return _scanView;
}


#pragma mark - AVCaptureMetadataOutputObjectsDelegate
/// 二维码扫描回调
- (void)captureOutput: (AVCaptureOutput *)captureOutput didOutputMetadataObjects: (NSArray *)metadataObjects fromConnection: (AVCaptureConnection *)connection {
    [self.session stopRunning];
    if (metadataObjects.count > 0 && self.complete) {
        AVMetadataMachineReadableCodeObject * metadataObject = metadataObjects[0];
        NSString * codeInfo = metadataObject.stringValue;
        self.complete(self, codeInfo);
    }
}


#pragma mark - UIImagePickerControllerDelegate
/// 图片选择回调
- (void)imagePickerController: (UIImagePickerController *)picker didFinishPickingMediaWithInfo: (NSDictionary *)info {
    UIImage * image = info[UIImagePickerControllerOriginalImage];
    CIDetector * detector = [CIDetector detectorOfType: CIDetectorTypeQRCode context: nil options: @{ CIDetectorAccuracy : CIDetectorAccuracyHigh }];
    [picker dismissViewControllerAnimated: YES completion: ^{
        NSArray * features = [detector featuresInImage: [CIImage imageWithCGImage: image.CGImage]];
        if (features.count >= 1) {
            [self stopScanning];
            if (self.complete) {
                CIQRCodeFeature * feature = [features objectAtIndex: 0];
                NSString * resultString = feature.messageString;
                self.complete(self, resultString);
            }
        } else {
            [self alertWithTitle: @"提示" message: @"该图片没有包含一个二维码！"];
        }
    }];
}


@end
