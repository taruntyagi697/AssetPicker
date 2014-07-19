/*
 * The MIT License (MIT)
 
 * Copyright (c) 2014 Tarun Tyagi. All rights reserved.
 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import <UIKit/UIKit.h>

#if !__has_feature(objc_arc)
#error AssetPicker requires ARC. Please turn on ARC for your project or \
add -fobjc-arc flag for AssetPicker.m file in Build Phases -> Compile Sources.
#endif

/*
 * An 'ALAsset' representing an asset in AssetsLibrary.
 * Provides Convenience for following :-
 * thumbnail
 * aspectRatioThumbnail
 * associated location, dates etc.
 * For more details, refer <AssetsLibrary/ALAsset.h>
 */
extern const NSString* APOriginalAsset;

/*
 * An NSURL of the fileURL form :-
 *  file:///Users/Me/Library/Application%20Support/iPhone%20Simulator/7.0/Applications/3C88CA44-4637-490D-9AB5-594DA4F1D924/Documents/E6F1A655-6C4E-4013-9B2B-11D4DACEDF8C.JPG
 * This provides convenience in accessing original data for the asset.
 */
extern const NSString* APAssetContentsURL;

/*
 * An 'NSString' representing type of the asset
 * Possible Values are - 'APAssetTypePhoto' & 'APAssetTypeVideo'.
 */
extern const NSString* APAssetType;
extern const NSString* APAssetTypePhoto;
extern const NSString* APAssetTypeVideo;

/*
 * Completion (Done) & Failure (Cancel) Blocks
 */
@class AssetPicker;
typedef void (^APCompletionHandler)(AssetPicker* picker, NSArray* assets);
typedef void (^APCancelHandler)(AssetPicker* picker);

@interface AssetPicker : UIViewController<UICollectionViewDataSource, UICollectionViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
{
    
}

/*
 * Class helper, only thing needed to push AssetPicker, 
 * get callbacks for Completion or Failure
 */
+(void)showAssetPickerIn:(UINavigationController*)navigationController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel;

/*
 * Class helper to clear disk memory claimed
 * while selecting assets.
 * Don't forget to use this after you're done with the assets.
 * Or you can yourself clear it using :-
 * [[NSFileManager defaultManager] removeItemAtURL:<--APAssetContentsURL-->]
 * for one by one asset clearing as needed.
 * Following method clears all the local copies present.
 */
+(void)clearLocalCopiesForAssets;

@end
