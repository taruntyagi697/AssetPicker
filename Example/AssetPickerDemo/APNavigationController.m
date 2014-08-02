//
//  APNavigationController.m
//  AssetPickerDemo
//
//  Created by Tarun Tyagi on 23/07/14.
//  Copyright (c) 2014 Tarun Tyagi. All rights reserved.
//

#import "APNavigationController.h"

@implementation APNavigationController

-(BOOL)shouldAutorotate
{
    return YES;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
