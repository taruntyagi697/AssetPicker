# AssetPicker - iOS (Objective-C)

`AssetPicker` is a `UIViewController` subclass that provides an alternative solution to standard UIImagePickerController. Highlights are :-
* Have both modes within single screen (Use Library or Use Camera).
* Select Multiple Assets (Photos / Videos).
* Browse all the albums within one screen.
* Filters :- Photos(Default), Videos, All
* Supports Portrait & Landscape Modes. (Autorotation supported (UIInterfaceOrientationMaskAllButUpsideDown))
* Uses Blocks for completion & cancel (Maintains integrity of code)
* Provides original ALAsset in returned response. (Better use it's properties)
* Provides ContentsURL for both Photos & Videos. (No UIImage directly, memory issues with multiple selection)
* Considers standard TabBarHeight and leaves space for that if set YES.
* Set Maximum Limits Independently on Photos, Videos, Assets.

## Requirements

* iOS 6.0 or later, ARC is must.
* QuartzCore.Framework
* AssetsLibrary.Framework

## Installation
* Like CocoaPods, just add this to your podfile-
```
pod 'AssetPicker'
```
* Want the source directly, just copy the AssetPicker folder (Art & Source).

## How To Use

Configuring AssetPicker is just like this :
```objective-c
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
```
and your work is done. AssetPicker does it all for you.
* It uses AssetsLibrary to fetch Albums Info, populates it into a nice UI.
* Provides all the albums browsing within one screen.
* Provides Camera option for new photo / video capture.

## iPad Portrait
![iPad_Portrait] (https://raw.githubusercontent.com/taruntyagi697/AssetPicker/master/Screenshots/iPad_Portrait.png)
## iPad Landscape
![iPad_Landscape] (https://raw.githubusercontent.com/taruntyagi697/AssetPicker/master/Screenshots/iPad_Landscape.png)

## iPhone Portrait
![iPhone_Portrait] (https://raw.githubusercontent.com/taruntyagi697/AssetPicker/master/Screenshots/iPhone_Portrait.png)
## iPhone Landscape
![iPhone_Landscape] (https://raw.githubusercontent.com/taruntyagi697/AssetPicker/master/Screenshots/iPhone_Landscape.png)
    
## Demo App
    Demo app includes just the above 'How To Use' code for reference.