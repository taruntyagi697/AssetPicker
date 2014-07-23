//
//  APDViewController.h
//  AssetPickerDemo
//
//  Created by Tarun Tyagi on 09/07/14.
//  Copyright (c) 2014 Tarun Tyagi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface APDViewController : UIViewController
{
    IBOutlet UIButton* iPad_GoToAssetPickerBtn;
    IBOutlet UIButton* iPhone_GoToAssetPickerBtn;
    
    UIButton* goToAssetPickerBtn;
}

-(IBAction)goToAssetPickerBtnAction:(UIButton*)sender;

@end
