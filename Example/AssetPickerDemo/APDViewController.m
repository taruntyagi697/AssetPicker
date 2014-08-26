//
//  APDViewController.m
//  AssetPickerDemo
//
//  Created by Tarun Tyagi on 09/07/14.
//  Copyright (c) 2014 Tarun Tyagi. All rights reserved.
//

#import "APDViewController.h"
#import "AssetPicker.h"

#define IsPad ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

#define ScreenWidth  [UIScreen mainScreen].bounds.size.width
#define ScreenHeight [UIScreen mainScreen].bounds.size.height

#define StatusBarHeight     ([UIApplication sharedApplication].statusBarHidden ? 0 : 20)
#define NavBarHeightFor(vc) (vc.navigationController.navigationBarHidden ? 0 : 44)

@interface APDViewController ()

@end

@implementation APDViewController

-(void)viewDidLoad
{
    [super viewDidLoad];
    
    goToAssetPickerBtn = (IsPad ? iPad_GoToAssetPickerBtn : iPhone_GoToAssetPickerBtn);
}

-(IBAction)goToAssetPickerBtnAction:(UIButton*)sender
{
    [AssetPicker showAssetPickerIn:self.navigationController
              maximumAllowedPhotos:4
              maximumAllowedVideos:4
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

-(void)viewWillAppear:(BOOL)animated
{
    [self setButtonInCenterForOrientation:[UIApplication sharedApplication].statusBarOrientation];
}

#pragma mark
#pragma mark<Autorotation Support>
#pragma mark

-(BOOL)shouldAutorotate
{
    return YES;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                               duration:(NSTimeInterval)duration
{
    [self setButtonInCenterForOrientation:toInterfaceOrientation];
}

#pragma mark
#pragma mark<Helpers>
#pragma mark

-(void)setButtonInCenterForOrientation:(UIInterfaceOrientation)orientation
{
    [UIView animateWithDuration:0.25f animations:^{
        BOOL isPortrait = UIInterfaceOrientationIsPortrait(orientation);
        CGFloat newWidth = (isPortrait?ScreenWidth:ScreenHeight);
        CGFloat newHeight = (isPortrait?ScreenHeight:ScreenWidth)-StatusBarHeight-NavBarHeightFor(self);
        
        goToAssetPickerBtn.center = CGPointMake(newWidth/2, newHeight/2);
    }];
}

@end
