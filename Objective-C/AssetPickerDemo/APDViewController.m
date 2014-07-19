//
//  APDViewController.m
//  AssetPickerDemo
//
//  Created by Tarun Tyagi on 09/07/14.
//  Copyright (c) 2014 Tarun Tyagi. All rights reserved.
//

#import "APDViewController.h"
#import "AssetPicker.h"

@interface APDViewController ()

@end

@implementation APDViewController

-(void)viewDidLoad
{
    [super viewDidLoad];
}

-(IBAction)goToAssetPickerBtnAction:(UIButton*)sender
{
    [AssetPicker showAssetPickerIn:self.navigationController
                 completionHandler:^(AssetPicker* picker, NSArray* assets)
     {
         NSLog(@"Assets --> %@", assets);
         
         // Do your stuff here
         
         // All done with the resources, let's reclaim disk memory
         [AssetPicker clearLocalCopiesForAssets];
     }
                     cancelHandler:^(AssetPicker* picker)
     {
         NSLog(@"Cancelled.");
     }];
}

@end
