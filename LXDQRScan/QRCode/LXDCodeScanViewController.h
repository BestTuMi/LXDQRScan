//
//  LXDCodeScanViewController.h
//  KamoClient
//
//  Created by linxinda on 2017/2/14.
//  Copyright © 2017年 Jolimark. All rights reserved.
//

#import <UIKit/UIKit.h>

/*!
 *  @brief  二维码扫描
 */
@interface LXDCodeScanViewController : UIViewController

- (instancetype)initWithComplete: (void(^)(LXDCodeScanViewController * scanVC, NSString * codeInfo))complete;

@end
