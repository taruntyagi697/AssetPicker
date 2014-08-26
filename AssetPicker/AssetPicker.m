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

#import "AssetPicker.h"
#import <AssetsLibrary/AssetsLibrary.h>

// Some useful macros to avoid rewriting some pretty basic stuff repeatedly
#define Application  [UIApplication sharedApplication]
#define FileManager  [NSFileManager defaultManager]
#define iOSVersion   [[[UIDevice currentDevice] systemVersion] floatValue]

#define IsPad ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
#define IsPortrait UIInterfaceOrientationIsPortrait([Application statusBarOrientation])

#define WindowSize      [UIScreen mainScreen].bounds.size
#define PortraitBounds  CGRectMake(0,0,WindowSize.width,WindowSize.height)
#define LandscapeBounds CGRectMake(0,0,WindowSize.height,WindowSize.width)

#define ScreenBounds (IsPortrait ? PortraitBounds : LandscapeBounds)
#define ScreenWidth  ScreenBounds.size.width
#define ScreenHeight ScreenBounds.size.height

#define StatusBarHeight     (Application.statusBarHidden ? 0 : 20)
#define NavBarHeightFor(vc) (vc.navigationController.navigationBarHidden ? 0 : (IsPad?44:(IsPortrait?44:32)))
#define TabBarHeight        (IsPad?56:49)

#define ThemeNavBarColor [UIColor whiteColor]
#define FontWithSize(s)  [UIFont systemFontOfSize:s]

#define UIColorWithRGBA(r,g,b,a) \
[UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]

#define Image(i) [UIImage imageNamed:i]

#define FormatString(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]

#if DEBUG
#define APLog(format, ...) NSLog(format, ##__VA_ARGS__)
#else
#define APLog(format, ...)
#endif

#define AssetsLibrary [AssetPicker assetsLibrary]

#define AlbumName   @"AlbumName"
#define AlbumAssets @"AlbumAssets"

#define AvailableAssetsCollectionItem   @"AvailableAssetsCollectionItem"
#define AvailableAssetsCollectionHeader @"AvailableAssetsCollectionHeader"

#define NotificationCenter         [NSNotificationCenter defaultCenter]
#define ItemTappedNotification     @"ItemTappedNotification"

#define BytesWritten @"BytesWritten"
#define ChunkSize    ((1024*1024)/4)

#define AssetInfoLoadQueue @"AssetInfoLoadQueue"
#define AssetWriteQueue    @"AssetWriteQueue"

#define AssetWriteDirectoryPath \
[NSHomeDirectory() stringByAppendingFormat:@"/Documents/AssetPickerTemp"]

#define CameraReturnedAssetWritten @"CameraReturnedAssetWritten"

#define DefaultMaximumPhotos 5
#define DefaultMaximumVideos 5
#define DefaultMaximumAssets (DefaultMaximumPhotos+DefaultMaximumVideos)

// External Variables' DEFINITIONS
const NSString* APOriginalAsset = @"APOriginalAsset";
const NSString* APAssetContentsURL = @"APAssetContentsURL";

const NSString* APAssetType = @"APAssetType";
const NSString* APAssetTypePhoto = @"APAssetTypePhoto";
const NSString* APAssetTypeVideo = @"APAssetTypeVideo";

//Asset SelectionLimit Trackers
NSUInteger maximumPhotosAllowed;
NSUInteger selectedPhotosCount;

NSUInteger maximumVideosAllowed;
NSUInteger selectedVideosCount;

NSUInteger maximumAssetsAllowed;
NSUInteger selectedAssetsCount;

// Filter type
typedef enum
{
    APFilterTypePhotos,
    APFilterTypeVideos,
    APFilterTypeAll
}APFilterType;

/*
 * CollectionViewCell subclass for AssetPicker CollectionView
 * Doesn't use standard Selection / Deselection
 * Implements a custom solution 
 * (NSNotificationCenter instead of regular delegate callbacks)
 */
#pragma mark
#pragma mark<@interface APAvailableAssetsCollectionItem>
#pragma mark

typedef enum
{
    APCollectionCellTypeInvalid = 0,
    APCollectionCellTypePhoto,
    APCollectionCellTypeVideo
}APCollectionCellType;

@interface APAvailableAssetsCollectionItem : UICollectionViewCell
{
    
}
@property(nonatomic,assign)APCollectionCellType type;
@property(nonatomic,strong)UIImageView* selectedCheckIcon;

@end

@implementation APAvailableAssetsCollectionItem

-(id)initWithFrame:(CGRect)frame
{
    if(self = [super initWithFrame:frame])
    {
        CGFloat iconSize = IsPad?20:14;
        _selectedCheckIcon = [[UIImageView alloc] initWithFrame:
                              CGRectMake(2, 2, iconSize, iconSize)];
        _selectedCheckIcon.image = Image(@"ap_check.png");
        [self addSubview:_selectedCheckIcon];
        
        _selectedCheckIcon.hidden = YES;
        
        for(UIGestureRecognizer* gr in self.gestureRecognizers)
            [self removeGestureRecognizer:gr];
        
        UITapGestureRecognizer* tapRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(itemTapped:)];
        [self addGestureRecognizer:tapRecognizer];
    }
    
    return self;
}

-(void)itemTapped:(UITapGestureRecognizer*)tapRecognizer
{
    if((selectedAssetsCount == maximumAssetsAllowed ||
        selectedPhotosCount == maximumPhotosAllowed ||
        selectedVideosCount == maximumVideosAllowed) && !self.selected)
    {
        NSString* title = @"Maximum Limit Reached!";
        NSString* message = @"";
        NSString* photoStr = (maximumPhotosAllowed != 1) ? @"Photos" : @"Photo";
        NSString* videoStr = (maximumVideosAllowed != 1) ? @"Videos" : @"Video";
        
        if((selectedAssetsCount == maximumAssetsAllowed) ||
           
           (selectedPhotosCount == maximumPhotosAllowed &&
            maximumAssetsAllowed > maximumPhotosAllowed &&
            self.type == APCollectionCellTypePhoto) ||
           
           (selectedVideosCount == maximumVideosAllowed &&
            maximumAssetsAllowed > maximumVideosAllowed &&
            self.type == APCollectionCellTypeVideo))
        {
            if(maximumPhotosAllowed == 0 && maximumVideosAllowed == 0)
            {
                NSString* assetsStr = (maximumAssetsAllowed != 1) ? @"Assets" : @"Asset";
                message = [NSString stringWithFormat:
                           @"You can only select a maximum of %d %@ at a time.",
                           maximumAssetsAllowed, assetsStr];
            }
            else
            {
                message = [NSString stringWithFormat:
                           @"You can only select a maximum of %d %@ & %d %@ at a time.",
                           maximumPhotosAllowed, photoStr, maximumVideosAllowed, videoStr];
            }
        }
        else if(selectedPhotosCount == maximumPhotosAllowed &&
                maximumAssetsAllowed == maximumPhotosAllowed &&
                self.type == APCollectionCellTypePhoto)
        {
            message = [NSString stringWithFormat:
                       @"You can only select a maximum of %d %@ at a time.",
                       maximumPhotosAllowed, photoStr];
        }
        else if(selectedVideosCount == maximumVideosAllowed &&
                maximumAssetsAllowed == maximumVideosAllowed &&
                self.type == APCollectionCellTypeVideo)
        {
            message = [NSString stringWithFormat:
                       @"You can only select a maximum of %d %@ at a time.",
                       maximumVideosAllowed, videoStr];
        }
        
        if([message length] > 0)
        {
            [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil
                              cancelButtonTitle:@"Okay" otherButtonTitles:nil] show];
            
            return;
        }
    }
    
    self.selected = !self.selected;
    
    if(self.selected)
    {
        if(self.type == APCollectionCellTypePhoto)
            selectedPhotosCount++;
        else
            selectedVideosCount++;
    }
    else
    {
        if(self.type == APCollectionCellTypePhoto)
            selectedPhotosCount--;
        else
            selectedVideosCount--;
    }
    selectedAssetsCount = selectedPhotosCount+selectedVideosCount;
    
    [NotificationCenter postNotificationName:ItemTappedNotification object:self];
}

-(void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    
    UIImageView* imgVw = (UIImageView*)[self.contentView viewWithTag:11111];
    if(selected)
    {
        imgVw.alpha = 0.5f;
        _selectedCheckIcon.hidden = NO;
    }
    else
    {
        imgVw.alpha = 1.0f;
        _selectedCheckIcon.hidden = YES;
    }
}

-(void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    
    UIImageView* imgVw = (UIImageView*)[self.contentView viewWithTag:11111];
    imgVw.alpha = 1.0f;
    _selectedCheckIcon.hidden = YES;
}

@end

/*
 * ALAsset category for isEqual: support
 * for asset comparisions.
 * It considers only 'ALAssetPropertyAssetURL' for equality
 * Can be updated as needed.
 */
#pragma mark
#pragma mark<@interface ALAsset(Compare)>
#pragma mark

@interface ALAsset (Compare)

-(BOOL)isEqualToAsset:(ALAsset*)asset;

@end

@implementation ALAsset (Compare)

-(BOOL)isEqualToAsset:(ALAsset*)asset
{
    if([[self valueForProperty:ALAssetPropertyAssetURL] isEqual:
        [asset valueForProperty:ALAssetPropertyAssetURL]])
        return YES;
    
    return NO;
}

@end

/*
 * ALAsset existence, add, remove support with NSMutableArray
 * Useful while selection / deselection
 * Helps avoiding replicated entries in selectedAssets
 */
#pragma mark
#pragma mark<@interface NSMutableArray(Assets)>
#pragma mark

@interface NSMutableArray (Assets)

-(BOOL)containsAsset:(ALAsset*)asset;
-(void)addAsset:(ALAsset*)asset;
-(void)removeAsset:(ALAsset*)asset;

@end

@implementation NSMutableArray (Assets)

-(ALAsset*)existingAssetMatch:(ALAsset*)asset
{
    for(ALAsset* containedAsset in self)
    {
        if([containedAsset isEqualToAsset:asset])
            return containedAsset;
    }
    
    return nil;
}

-(BOOL)containsAsset:(ALAsset*)asset
{
    return ([self existingAssetMatch:asset] != nil);
}

-(void)addAsset:(ALAsset*)asset
{
    ALAsset* existingAsset = [self existingAssetMatch:asset];
    if(existingAsset == nil)
        [self addObject:asset];
}

-(void)removeAsset:(ALAsset*)asset
{
    ALAsset* existingAsset = [self existingAssetMatch:asset];
    if(existingAsset != nil)
        [self removeObject:existingAsset];
}

@end

/*
 * AssetPicker - IMPLEMENTATION
 * Uses AssetsLibrary as source for fetching the Assets
 * Provides In-Built Filtering support :-
 * Photos, Videos, All
 * Shows all the available ALBUMS in one UI (CollectionView with Sections)
 * Can always go for a new pic/video using Camera
 * Uses 'DispatchQueues' whenever needed in order to prevent
 * blocking the main thread.
 */

#pragma mark
#pragma mark<@interface AssetPicker>
#pragma mark

@interface AssetPicker ()
{
    // TransparentView to prevent user interaction while displaying pop-up
    UIView* clearViewForDisablingUI;
    
    // TopBar
    UIView* topBar;
    UIButton* backBtn;
    UIButton* filterBtn;
    UILabel* titleLbl;
    UIButton* cameraBtn;
    UIButton* doneBtn;
    
    /*
     * Remember what was the statusBarStyle & navigationBarColor
     * when AssetPicker launched
     */
    UIStatusBarStyle previousStatusBarStyle;
    UIColor* previousNavigationBarColor;
    
    // TopBar - Filter Options
    APFilterType filterType;
    
    // TopBar - Camera Options
    UIView* cameraOptionsContainer;
    UIImagePickerControllerCameraDevice cameraDevice;
    UIImagePickerControllerQualityType cameraQuality;
    UIImagePickerControllerCameraFlashMode cameraFlashMode;
    UIImagePickerControllerCameraCaptureMode cameraCaptureMode;
    
    // Loading Activity
    UIView* loadingShield;
    UIImageView* loadingImgVw;
    
    // Callbacks
    APCompletionHandler apCompletion;
    APCancelHandler apCancel;
    
    // Stored / Available(Filtered) Assets from AssetsLibrary
    NSMutableArray* storedAssets;
    NSMutableArray* availableAssets;
    
    // Collection For Selected Assets
    NSMutableArray* selectedAssets;
    
    // CollectionView - Grid
    UICollectionView* availableAssetsClctnVw;
    NSMutableDictionary* sectionHeaders;
    dispatch_queue_t assetInfoLoadQueue;
    
    // Considers Tab Bar
    BOOL isContainedInTabBarController;
    
    // Local(Documents) File Write Support
    long long totalBytesToWrite;
    long long totalBytesWritten;
    UILabel* writingFilesMessageLbl;
    UIProgressView* progressBar;
    
    // Requested Assets (To Be Sent With Completion)
    NSMutableArray* requestedAssets;
    dispatch_queue_t assetWriteQueue;
}

@end

@implementation AssetPicker

#pragma mark
#pragma mark<Initialization Helpers>
#pragma mark

+(ALAssetsLibrary*)assetsLibrary
{
    static ALAssetsLibrary* assetsLibrary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assetsLibrary = [[ALAssetsLibrary alloc] init];
    });
    
    return assetsLibrary;
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
                   considersTabBar:NO
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:DefaultMaximumPhotos
              maximumAllowedVideos:DefaultMaximumVideos
              maximumAllowedAssets:DefaultMaximumAssets
                   considersTabBar:isInTabBarController
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedPhotos:(NSUInteger)photosCount
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:photosCount
                   considersTabBar:NO
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedPhotos:(NSUInteger)photosCount
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:photosCount
              maximumAllowedVideos:0
              maximumAllowedAssets:photosCount
                   considersTabBar:isInTabBarController
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedVideos:(NSUInteger)videosCount
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedVideos:videosCount
                   considersTabBar:NO
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedVideos:(NSUInteger)videosCount
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:0
              maximumAllowedVideos:videosCount
              maximumAllowedAssets:videosCount
                   considersTabBar:isInTabBarController
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedPhotos:(NSUInteger)photosCount
    maximumAllowedVideos:(NSUInteger)videosCount
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:photosCount
              maximumAllowedVideos:videosCount
                   considersTabBar:NO
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedPhotos:(NSUInteger)photosCount
    maximumAllowedVideos:(NSUInteger)videosCount
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:photosCount
              maximumAllowedVideos:videosCount
              maximumAllowedAssets:photosCount+videosCount
                   considersTabBar:isInTabBarController
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedAssets:(NSUInteger)assetsCount
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedAssets:assetsCount
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedAssets:(NSUInteger)assetsCount
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    return [self showAssetPickerIn:navigationController
              maximumAllowedPhotos:0
              maximumAllowedVideos:0
              maximumAllowedAssets:assetsCount
                   considersTabBar:isInTabBarController
                 completionHandler:completion
                     cancelHandler:cancel];
}

+(void)showAssetPickerIn:(UINavigationController*)navigationController
    maximumAllowedPhotos:(NSUInteger)photosCount
    maximumAllowedVideos:(NSUInteger)videosCount
    maximumAllowedAssets:(NSUInteger)assetsCount
         considersTabBar:(BOOL)isInTabBarController
       completionHandler:(APCompletionHandler)completion
           cancelHandler:(APCancelHandler)cancel
{
    AssetPicker* picker = [[AssetPicker alloc] initWithCompletionHandler:completion
                                                           cancelHandler:cancel
                                                         considersTabBar:isInTabBarController
                                                    maximumAllowedPhotos:photosCount
                                                    maximumAllowedVideos:videosCount
                                                    maximumAllowedAssets:photosCount+videosCount];
    [navigationController pushViewController:picker animated:YES];
}

-(id)initWithCompletionHandler:(APCompletionHandler)completion
                 cancelHandler:(APCancelHandler)cancel
               considersTabBar:(BOOL)isInTabBarController
          maximumAllowedPhotos:(NSUInteger)photosCount
          maximumAllowedVideos:(NSUInteger)videosCount
          maximumAllowedAssets:(NSUInteger)assetsCount
{
    if(self = [super init])
    {
        apCompletion = completion;
        apCancel = cancel;
        isContainedInTabBarController = isInTabBarController;
        
        maximumPhotosAllowed = photosCount;
        maximumVideosAllowed = videosCount;
        maximumAssetsAllowed = assetsCount;
        
        selectedPhotosCount = 0;
        selectedVideosCount = 0;
        selectedAssetsCount = 0;
        
        storedAssets = [@[] mutableCopy];
        availableAssets = [@[] mutableCopy];
        
        selectedAssets = [@[] mutableCopy];
    }
    
    return self;
}

#pragma mark
#pragma mark<Clear Local Copies>
#pragma mark

+(void)clearLocalCopiesForAssets
{
    [FileManager removeItemAtPath:AssetWriteDirectoryPath error:nil];
}

#pragma mark
#pragma mark<View Life-Cycle>
#pragma mark

-(void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = ThemeNavBarColor;
    self.navigationItem.hidesBackButton = YES;
    
    previousStatusBarStyle = Application.statusBarStyle;
    [Application setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
    
    if(iOSVersion >= 7.0f)
    {
        self.edgesForExtendedLayout = UIRectEdgeNone;
        
        previousNavigationBarColor = self.navigationController.navigationBar.barTintColor;
        self.navigationController.navigationBar.barTintColor = ThemeNavBarColor;
    }
    else
    {
        previousNavigationBarColor = self.navigationController.navigationBar.tintColor;
        self.navigationController.navigationBar.tintColor = ThemeNavBarColor;
    }
    
    // Prepare clearView
    clearViewForDisablingUI = [[UIView alloc] initWithFrame:ScreenBounds];
    clearViewForDisablingUI.backgroundColor = [UIColor clearColor];
    [self.navigationController.view addSubview:clearViewForDisablingUI];
    [self.navigationController.view sendSubviewToBack:clearViewForDisablingUI];
    
    UITapGestureRecognizer* tapRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapOnTransparentView:)];
    [clearViewForDisablingUI addGestureRecognizer:tapRecognizer];
    
    // By Default, filter is PHOTOS
    filterType = APFilterTypePhotos;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepareTopBar];
        [self prepareLoading];
    });
    
    [self fetchAvailableAssets];
    
    assetWriteQueue = dispatch_queue_create([AssetWriteQueue UTF8String], NULL);
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [NotificationCenter addObserver:self
                           selector:@selector(collectionViewCellTapped:)
                               name:ItemTappedNotification
                             object:nil];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [NotificationCenter removeObserver:self];
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
    [UIView animateWithDuration:0.25f animations:^{
        BOOL isPortrait = UIInterfaceOrientationIsPortrait(toInterfaceOrientation);
        CGRect targetBounds = (isPortrait?PortraitBounds:LandscapeBounds);
        CGFloat newWidth = targetBounds.size.width;
        CGFloat newHeight = targetBounds.size.height-(isContainedInTabBarController?TabBarHeight:0);
        
        clearViewForDisablingUI.frame = targetBounds;
        
        CGFloat navBarHeight = NavBarHeightFor(self);
        CGFloat topBarHeight = 0;
        if((navBarHeight == 0 &&
            (IsPad || (!IsPad && UIInterfaceOrientationIsPortrait(toInterfaceOrientation)))) ||
           (navBarHeight == 44 && IsPad) ||
           (navBarHeight == 32 && toInterfaceOrientation == UIInterfaceOrientationPortrait))
        {
            topBarHeight = 44;
        }
        else
        {
            topBarHeight = 32;
        }
        
        topBar.frame = CGRectMake(0, ((iOSVersion>=7.0f && navBarHeight==0)?StatusBarHeight:0),
                                  newWidth, topBarHeight);
        
        CGFloat titleLblWidth = (IsPad?400:(isPortrait?170:300));
        
        backBtn.frame = CGRectMake((IsPad?3:0), (topBarHeight-30)/2, 36, 30);
        filterBtn.frame = CGRectMake((IsPad?60:40), (topBarHeight-30)/2, 30, 30);
        titleLbl.frame = CGRectMake((newWidth-titleLblWidth)/2, (topBarHeight-40)/2, titleLblWidth, 40);
        cameraBtn.frame = CGRectMake((newWidth-(IsPad?90:(isPortrait?71:80))), (topBarHeight-30)/2, 30, 30);
        doneBtn.frame = CGRectMake((newWidth-(IsPad?40:(isPortrait?34:40))), (topBarHeight-30)/2, 33, 30);
        
        availableAssetsClctnVw.frame =
        CGRectMake(0, ((navBarHeight>0)?0:topBarHeight+((iOSVersion>=7.0f)?StatusBarHeight:0)),
                   newWidth, (newHeight-topBarHeight-StatusBarHeight));
        
        cameraOptionsContainer.frame =
        CGRectMake(CGRectGetMidX(cameraBtn.frame)-170,
                   StatusBarHeight+topBarHeight-9+(topBarHeight==32?6:0), 200, 258);
        
        [self reloadAllSectionHeaderLabelWidthsForScreenWidth:newWidth];
        
        loadingShield.frame = targetBounds;
        loadingImgVw.center = CGPointMake(targetBounds.size.width/2, targetBounds.size.height/2);
        
        writingFilesMessageLbl.frame = CGRectMake(20, (newHeight-120)/2, newWidth-40, 40);
        progressBar.frame = CGRectMake(50, (newHeight/2)+30, newWidth-100, 0);
    }];
}

#pragma mark
#pragma mark<Helpers>
#pragma mark

-(void)addTopBar
{
    CGFloat navBarHeight = NavBarHeightFor(self);
    if(navBarHeight > 0 && navBarHeight < 44)
    {
        topBar.frame = CGRectMake(0, (navBarHeight-44)/2, topBar.frame.size.width, navBarHeight);
    }
    else
    {
        CGFloat topBarHeight = IsPad?44:(IsPortrait?44:32);
        topBar.frame = CGRectMake(0, (iOSVersion>=7.0f && navBarHeight==0)?StatusBarHeight:0,
                                  topBar.frame.size.width, topBarHeight);
        
        if(topBarHeight != 44)
        {
            for(UIView* sbvw in topBar.subviews)
            {
                CGRect frame = sbvw.frame;
                frame.origin.y = (topBarHeight-frame.size.height)/2;
                sbvw.frame = frame;
            }
        }
    }
    
    if(navBarHeight > 0)
        [self.navigationController.navigationBar addSubview:topBar];
    else
        [self.view addSubview:topBar];
    
    topBar.alpha = 0.0f;
    [UIView animateWithDuration:0.25f animations:^{
        topBar.alpha = 1.0f;
    }];
}

-(void)fetchAvailableAssets
{
    [self showLoading];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [AssetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll
                                     usingBlock:^(ALAssetsGroup* group, BOOL* stop)
         {
             if(group != nil)
             {
                 NSMutableArray* albumAssets = [@[] mutableCopy];
                 
                 [group enumerateAssetsUsingBlock:
                  ^(ALAsset* result, NSUInteger index, BOOL* stop)
                  {
                      if(result != nil)
                          [albumAssets addObject:result];
                  }];
                 
                 NSString* albumName = [group valueForProperty:ALAssetsGroupPropertyName];
                 
                 NSDictionary* albumInfo = @{AlbumName:albumName,
                                             AlbumAssets:albumAssets};
                 
                 if([albumName isEqualToString:@"Saved Photos"] ||
                    [albumName isEqualToString:@"Camera Roll"])
                 {
                     [storedAssets insertObject:albumInfo atIndex:0];
                 }
                 else
                 {
                     [storedAssets addObject:albumInfo];
                 }
             }
             
             if(group == nil || *stop)
             {
                 [self stopLoading];
                 
                 dispatch_async(dispatch_get_main_queue(), ^{
                     [self addAvailableAssetsCollectionView];
                 });
             }
         }
                                   failureBlock:^(NSError* error)
         {
             APLog(@"Couldn't fetch assets from AssetsLibrary. Reason :- %@",
                   error.localizedDescription);
             
             if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusDenied)
             {
                 NSString* applicationName =
                 [[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"];
                 
                 NSString* message =
                 FormatString(@"You denied '%@' to access your PHOTOS earlier.\n"
                              "To enable PHOTOS access, go to Settings -> Privacy "
                              "-> Photos -> %@", applicationName, applicationName);
                 
                 [[[UIAlertView alloc] initWithTitle:@"Grant PHOTOS Permission !"
                                             message:message
                                            delegate:nil
                                   cancelButtonTitle:@"Okay"
                                   otherButtonTitles:nil] show];
             }
         }];
    });
}

-(void)addAvailableAssetsCollectionView
{
    CGFloat size = IsPad?140:76;
    CGFloat padding = IsPad?10:5;
    
    UICollectionViewFlowLayout* layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = IsPad?10:2;
    layout.minimumInteritemSpacing = 0;
    layout.itemSize = CGSizeMake(size, size);
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.headerReferenceSize = CGSizeMake(ScreenWidth, IsPad?35:25);
    layout.footerReferenceSize = CGSizeZero;
    layout.sectionInset = UIEdgeInsetsMake(padding, padding, padding, padding);
    
    CGFloat navBarHeight = NavBarHeightFor(self);
    CGRect frame = CGRectMake(0, ((navBarHeight>0)?0:topBar.frame.size.height+
                                  ((iOSVersion>=7.0f)?StatusBarHeight:0)),
                              ScreenWidth, (ScreenHeight-topBar.frame.size.height-StatusBarHeight-
                               (isContainedInTabBarController?TabBarHeight:0)));
    availableAssetsClctnVw =
    [[UICollectionView alloc] initWithFrame:frame
                       collectionViewLayout:layout];
    availableAssetsClctnVw.dataSource = self;
    availableAssetsClctnVw.delegate = self;
    availableAssetsClctnVw.allowsMultipleSelection = YES;
    availableAssetsClctnVw.backgroundColor = UIColorWithRGBA(230, 230, 230, 1);
    [self.view addSubview:availableAssetsClctnVw];
    
    [availableAssetsClctnVw registerClass:[APAvailableAssetsCollectionItem class]
               forCellWithReuseIdentifier:AvailableAssetsCollectionItem];
    
    [availableAssetsClctnVw registerClass:[UICollectionReusableView class]
               forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                      withReuseIdentifier:AvailableAssetsCollectionHeader];
    
    availableAssets = [self filteredAssets];
    [availableAssetsClctnVw reloadData];
    
    sectionHeaders = [@{} mutableCopy];
    assetInfoLoadQueue = dispatch_queue_create([AssetInfoLoadQueue UTF8String], NULL);
}

-(NSMutableArray*)filteredAssets
{
    if(filterType == APFilterTypeAll)
        return [storedAssets mutableCopy];
    
    NSPredicate* predicate = nil;
    if(filterType == APFilterTypePhotos)
    {
        predicate = [NSPredicate predicateWithBlock:
                     ^BOOL(ALAsset* asset, NSDictionary* bindings) {
                         NSString* assetType = [asset valueForProperty:ALAssetPropertyType];
                         return [assetType isEqualToString:ALAssetTypePhoto];
                     }];
    }
    else if(filterType == APFilterTypeVideos)
    {
        predicate = [NSPredicate predicateWithBlock:
                     ^BOOL(ALAsset* asset, NSDictionary* bindings) {
                         NSString* assetType = [asset valueForProperty:ALAssetPropertyType];
                         return [assetType isEqualToString:ALAssetTypeVideo];
                     }];
    }
    
    NSMutableArray* filteredAssets = [@[] mutableCopy];
    for(NSMutableDictionary* storedAlbumInfo in storedAssets)
    {
        NSMutableArray* albumAssets = [storedAlbumInfo[AlbumAssets] mutableCopy];
        NSArray* filteredAlbumAssets = [albumAssets filteredArrayUsingPredicate:predicate];
        if(filteredAlbumAssets == nil)
            filteredAlbumAssets = [@[] mutableCopy];
        
        NSMutableDictionary* filteredAlbumInfo = [@{} mutableCopy];
        filteredAlbumInfo[AlbumName] = storedAlbumInfo[AlbumName];
        filteredAlbumInfo[AlbumAssets] = [filteredAlbumAssets mutableCopy];
        
        [filteredAssets addObject:filteredAlbumInfo];
    }
    
    return filteredAssets;
}

-(void)refreshSectionHeader:(UIView*)headerVw forIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* albumInfo = availableAssets[indexPath.section];
    
    NSInteger selectedPhotosCount = 0;
    NSInteger selectedVideosCount = 0;
    NSMutableArray* storedAlbumAssets = storedAssets[indexPath.section][AlbumAssets];
    for(ALAsset* selAsset in selectedAssets) {
        for(ALAsset* albumAsset in storedAlbumAssets) {
            if([selAsset isEqualToAsset:albumAsset]) {
                NSString* assetTypeStr = [selAsset valueForProperty:ALAssetPropertyType];
                if([assetTypeStr isEqualToString:ALAssetTypePhoto])
                    selectedPhotosCount++;
                else if([assetTypeStr isEqualToString:ALAssetTypeVideo])
                    selectedVideosCount++;
                
                break;
            }
        }
    }
    
    UILabel* albumNameLbl = (UILabel*)[headerVw viewWithTag:12345];
    if([albumInfo[AlbumName] isEqualToString:@"Saved Photos"] ||
       [albumInfo[AlbumName] isEqualToString:@"Camera Roll"])
    {
        NSString* photosStr = (selectedPhotosCount == 1) ? @"Photo" : @"Photos";
        NSString* videosStr = (selectedVideosCount == 1) ? @"Video" : @"Videos";
        
        albumNameLbl.text = [NSString stringWithFormat:
                             @"%@ (%d) - (%d %@ + %d %@) Selected",
                             albumInfo[AlbumName], [albumInfo[AlbumAssets] count],
                             selectedPhotosCount, photosStr, selectedVideosCount, videosStr];
    }
    else
    {
        NSString* itemsStr = ((selectedPhotosCount+selectedVideosCount) == 1) ? @"Item" : @"Items";
        albumNameLbl.text = [NSString stringWithFormat:
                             @"%@ (%d) - %d %@ Selected",
                             albumInfo[AlbumName], [albumInfo[AlbumAssets] count],
                             (selectedPhotosCount+selectedVideosCount), itemsStr];
    }
}

-(void)reloadAllSectionHeaderLabelWidthsForScreenWidth:(CGFloat)newWidth
{
    [sectionHeaders enumerateKeysAndObjectsUsingBlock:
     ^(NSIndexPath* key, UIView* obj, BOOL *stop)
     {
         UILabel* albumNameLbl = (UILabel*)[obj viewWithTag:12345];
         CGRect frame = albumNameLbl.frame;
         frame.size.width = (newWidth-(2*frame.origin.x));
         albumNameLbl.frame = frame;
     }];
}

-(void)reloadAllSectionHeaders
{
    [sectionHeaders enumerateKeysAndObjectsUsingBlock:
     ^(NSIndexPath* key, UIView* obj, BOOL *stop)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             [self refreshSectionHeader:obj forIndexPath:key];
         });
     }];
}

-(void)reloadSectionHeadersAndAnyVisibleMatchingItemUsingIndexPath:(NSIndexPath*)indexPath
{
    [self reloadAllSectionHeaders];
    
    ALAsset* targetAsset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    
    NSArray* visibleCellIndexPaths = [availableAssetsClctnVw indexPathsForVisibleItems];
    for(NSIndexPath* ip in visibleCellIndexPaths)
    {
        if(ip.section == indexPath.section && ip.item == indexPath.item)
            continue;
        
        ALAsset* availableAsset = availableAssets[ip.section][AlbumAssets][ip.row];
        if([availableAsset isEqualToAsset:targetAsset])
            [availableAssetsClctnVw reloadItemsAtIndexPaths:@[ip]];
    }
}

-(void)refreshSavedPhotosAddAssetWithURL:(NSURL*)assetURL
{
    [AssetsLibrary assetForURL:assetURL
                   resultBlock:^(ALAsset* asset)
     {
         if(asset != nil)
         {
             [selectedAssets addAsset:asset];
             
             //[storedAssets[0][AlbumAssets] addObject:asset];
             NSMutableDictionary* savedPhotosAlbum = [storedAssets[0] mutableCopy];
             NSMutableArray* savedPhotosAlbumAssets = [savedPhotosAlbum[AlbumAssets] mutableCopy];
             [savedPhotosAlbumAssets insertObject:asset atIndex:0];
             savedPhotosAlbum[AlbumAssets] = savedPhotosAlbumAssets;
             [storedAssets replaceObjectAtIndex:0 withObject:savedPhotosAlbum];
             
             NSString* assetType = [asset valueForProperty:ALAssetPropertyType];
             
             if((filterType == APFilterTypeAll) ||
                ([assetType isEqualToString:ALAssetTypePhoto] && filterType == APFilterTypePhotos) ||
                ([assetType isEqualToString:ALAssetTypeVideo] && filterType == APFilterTypeVideos))
             {
                 //[availableAssets[0][AlbumAssets] addObject:asset];
                 savedPhotosAlbum = [availableAssets[0] mutableCopy];
                 savedPhotosAlbumAssets = [savedPhotosAlbum[AlbumAssets] mutableCopy];
                 [savedPhotosAlbumAssets insertObject:asset atIndex:0];
                 savedPhotosAlbum[AlbumAssets] = savedPhotosAlbumAssets;
                 [availableAssets replaceObjectAtIndex:0 withObject:savedPhotosAlbum];
                 
                 NSIndexPath* indexPath = [NSIndexPath indexPathForItem:0 inSection:0];
                 [availableAssetsClctnVw insertItemsAtIndexPaths:@[indexPath]];
                 [availableAssetsClctnVw scrollToItemAtIndexPath:indexPath
                                                atScrollPosition:UICollectionViewScrollPositionTop
                                                        animated:YES];
                 
                 double delayInSeconds = 0.75f;
                 dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                 dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                     APAvailableAssetsCollectionItem* item = (APAvailableAssetsCollectionItem*)
                     [availableAssetsClctnVw cellForItemAtIndexPath:indexPath];
                     item.selected = YES;
                     [NotificationCenter postNotificationName:ItemTappedNotification object:item];
                 });
             }
             
             [self reloadAllSectionHeaders];
         }
     }
                  failureBlock:^(NSError* error)
     {
         APLog(@"Couldn't get last saved asset from Assets Library. Reason :- %@",
               error.localizedDescription);
     }];
}

-(void)removeTopBarNClearViewProvideNavigationBarOriginalAppearance
{
    [UIView animateWithDuration:0.25f animations:^{topBar.alpha = 0.0f;}
                     completion:^(BOOL finished){[topBar removeFromSuperview];}];
    
    [clearViewForDisablingUI removeFromSuperview];
    
    [Application setStatusBarStyle:previousStatusBarStyle animated:YES];
    
    if(iOSVersion >= 7.0f)
        self.navigationController.navigationBar.barTintColor = previousNavigationBarColor;
    else
        self.navigationController.navigationBar.tintColor = previousNavigationBarColor;
}

#pragma mark
#pragma mark<UIGestureRecognizer Methods>
#pragma mark

-(void)handleTapOnTransparentView:(UITapGestureRecognizer*)tapRecognizer
{
    [self.navigationController.view sendSubviewToBack:clearViewForDisablingUI];
    [cameraOptionsContainer removeFromSuperview];
}

#pragma mark
#pragma mark<TopBar>
#pragma mark

-(void)prepareTopBar
{
    topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, 44)];
    topBar.backgroundColor = ThemeNavBarColor;
    
    backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.imageEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 14);
    backBtn.backgroundColor = [UIColor clearColor];
    [backBtn setImage:Image(@"ap_back.png") forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(backBtnAction:)
      forControlEvents:UIControlEventTouchUpInside];
    
    filterBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [filterBtn setImage:Image(@"ap_photo.png") forState:UIControlStateNormal];
    [filterBtn addTarget:self action:@selector(filterBtnAction:)
        forControlEvents:UIControlEventTouchUpInside];
    
    titleLbl = [[UILabel alloc] init];
    titleLbl.backgroundColor = [UIColor clearColor];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.textColor = UIColorWithRGBA(38, 38, 38, 1);
    titleLbl.font = FontWithSize(16.0f);
    titleLbl.numberOfLines = 0;
    
    cameraBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [cameraBtn setImage:Image(@"ap_camera.png") forState:UIControlStateNormal];
    [cameraBtn addTarget:self action:@selector(cameraBtnAction:)
        forControlEvents:UIControlEventTouchUpInside];
    
    doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [doneBtn setImage:Image(@"ap_done.png") forState:UIControlStateNormal];
    [doneBtn setImageEdgeInsets:UIEdgeInsetsMake(4, 3, 2, 3)];
    [doneBtn addTarget:self action:@selector(doneBtnAction:)
      forControlEvents:UIControlEventTouchUpInside];
    
    CGFloat titleLblWidth = (IsPad?400:(IsPortrait?170:300));
    
    backBtn.frame = CGRectMake((IsPad?3:0), 7, 36, 30);
    filterBtn.frame = CGRectMake((IsPad?60:40), 7, 30, 30);
    titleLbl.frame = CGRectMake((ScreenWidth-titleLblWidth)/2, 2, titleLblWidth, 40);
    cameraBtn.frame = CGRectMake((ScreenWidth-(IsPad?90:(IsPortrait?71:80))), 7, 30, 30);
    doneBtn.frame = CGRectMake((ScreenWidth-(IsPad?40:(IsPortrait?34:40))), 7, 33, 30);
    
    [topBar addSubview:backBtn];
    [topBar addSubview:filterBtn];
    [topBar addSubview:titleLbl];
    [topBar addSubview:cameraBtn];
    [topBar addSubview:doneBtn];
    
    if(maximumPhotosAllowed > 0 && maximumAssetsAllowed == maximumPhotosAllowed)
    {
        filterType = APFilterTypePhotos;
        filterBtn.hidden = YES;
    }
    else if(maximumVideosAllowed > 0 && maximumAssetsAllowed == maximumVideosAllowed)
    {
        filterType = APFilterTypeVideos;
        filterBtn.hidden = YES;
    }
    
    titleLbl.text = @"Select Photos/Videos From Library";
    
    [self addTopBar];
}

-(void)backBtnAction:(UIButton*)sender
{
    [self.navigationController popViewControllerAnimated:YES];
    [self removeTopBarNClearViewProvideNavigationBarOriginalAppearance];
    
    if(apCancel != nil)
    {
        apCancel(self);
        apCancel = nil;
    }
}

-(void)filterBtnAction:(UIButton*)sender
{
    sender.imageEdgeInsets = UIEdgeInsetsZero;
    NSString* imageNameStr = @"";
    
    if(filterType == APFilterTypePhotos)
    {
        filterType = APFilterTypeVideos;
        imageNameStr = @"ap_video.png";
        sender.imageEdgeInsets = UIEdgeInsetsMake(7, 0, 3, 0);
    }
    else if(filterType == APFilterTypeVideos)
    {
        filterType = APFilterTypeAll;
        imageNameStr = @"ap_options.png";
    }
    else if(filterType == APFilterTypeAll)
    {
        filterType = APFilterTypePhotos;
        imageNameStr = @"ap_photo.png";
    }
    
    [sender setImage:Image(imageNameStr) forState:UIControlStateNormal];
    
    availableAssets = nil;
    availableAssets = [self filteredAssets];
    [availableAssetsClctnVw reloadData];
}

-(void)cameraBtnAction:(UIButton*)sender
{
    [self showCameraOptions];
}

-(void)doneBtnAction:(UIButton*)sender
{
    if([selectedAssets count] == 0)
    {
        [self.navigationController popViewControllerAnimated:YES];
        [self removeTopBarNClearViewProvideNavigationBarOriginalAppearance];
        
        if(apCompletion != nil)
        {
            apCompletion(self, @[]);
            apCompletion = nil;
        }
        
        return;
    }
    
    totalBytesToWrite = 0;
    totalBytesWritten = 0;
    for(ALAsset* asset in selectedAssets)
    {
        ALAssetRepresentation* representation = [asset defaultRepresentation];
        totalBytesToWrite += [representation size];
    }
    
    writingFilesMessageLbl = [[UILabel alloc] initWithFrame:
                              CGRectMake(20, (ScreenHeight-120)/2, ScreenWidth-40, 40)];
    writingFilesMessageLbl.backgroundColor = [UIColor clearColor];
    writingFilesMessageLbl.textAlignment = NSTextAlignmentCenter;
    writingFilesMessageLbl.textColor = [UIColor darkGrayColor];
    writingFilesMessageLbl.font = FontWithSize(16.0f);
    writingFilesMessageLbl.text = @"Writing files for your convenience!\n It won't take long...";
    writingFilesMessageLbl.numberOfLines = 0;
    [loadingShield addSubview:writingFilesMessageLbl];
    
    progressBar = [[UIProgressView alloc]
                   initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressBar.frame = CGRectMake(50, (ScreenHeight/2)+30, ScreenWidth-100, 0);
    progressBar.progressTintColor = UIColorWithRGBA(78,78,78,1);
    progressBar.trackTintColor = [UIColor lightGrayColor];
    [loadingShield addSubview:progressBar];
    progressBar.progress = 0.0f;
    
    loadingShield.backgroundColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.75f];
    [self showLoading];
    
    [clearViewForDisablingUI removeFromSuperview];
    [topBar removeFromSuperview];
    [availableAssetsClctnVw removeFromSuperview];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self writeAssetsAndPrepareURLs];
    });
}

#pragma mark
#pragma mark<Write Assets>
#pragma mark

-(void)writeAssetsAndPrepareURLs
{
    requestedAssets = [@[] mutableCopy];
    
    for(ALAsset* asset in selectedAssets)
    {
        dispatch_async(assetWriteQueue, ^{
            // assets-library://asset/asset.mp4?id=BB9B3F82-C547-4EC2-A3A3-98E36B84309D&ext=mp4
            NSURL* assetURL = [asset valueForProperty:ALAssetPropertyAssetURL];
            NSArray* assetURLStrComps = [assetURL.absoluteString
                                         componentsSeparatedByString:@"&ext="];
            NSString* extension = assetURLStrComps[1];
            NSString* uniqueID = [assetURLStrComps[0]
                                  componentsSeparatedByString:@"?id="][1];
            
            // Create Folder, if it's not there already
            if(![FileManager fileExistsAtPath:AssetWriteDirectoryPath])
            {
                [FileManager createDirectoryAtPath:AssetWriteDirectoryPath
                       withIntermediateDirectories:YES attributes:nil error:nil];
            }
            
            // Formulate fileURL to Write File to
            NSString* filePath = [AssetWriteDirectoryPath stringByAppendingFormat:
                                  @"/%@.%@",uniqueID,extension];
            NSURL* fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
            
            // Remove pre-existing file with same name
            [FileManager removeItemAtURL:fileURL error:nil];
            
            /*
             * Start/Create a file at URL, couldn't find a could be 'createFileAtURL:'
             * sibling of 'createFileAtPath:' in NSFileManager
             */
            NSMutableData* blankData = [NSMutableData data];
            [blankData setLength:0];
            [blankData writeToURL:fileURL atomically:YES];
            
            // Now that file is initialized at fileURL, get a fileHandle for writing
            NSFileHandle* fileHandle =
            [NSFileHandle fileHandleForWritingToURL:fileURL error:nil];
            
            /*
             * Write Asset's defaultRepresentation (Raw Bytes) in chunks
             * in order to avoid memory overhead (it's faster & efficient)
             * only write small chunks (1MB in this case)
             * Update Write Progress to UI.
             */
            ALAssetRepresentation* representation = [asset defaultRepresentation];
            long long offset = 0;
            long long size = [representation size];
            
            while(offset < size)
            {
                uint8_t buffer[ChunkSize];
                
                NSInteger bytesRead = [representation getBytes:buffer fromOffset:offset
                                                        length:ChunkSize error:nil];
                NSData* data = [NSData dataWithBytes:buffer length:bytesRead];
                [fileHandle writeData:data];
                
                offset += bytesRead;
                totalBytesWritten += bytesRead;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateProgress];
                });
            }
            
            // Asset is written to fileURL, contentsURL is available now
            NSMutableDictionary* requestedAssetInfo = [@{} mutableCopy];
            requestedAssetInfo[APOriginalAsset] = asset;
            
            NSString* assetType = [asset valueForProperty:ALAssetPropertyType];
            if([assetType isEqualToString:ALAssetTypePhoto])
                requestedAssetInfo[APAssetType] = APAssetTypePhoto;
            else if([assetType isEqualToString:ALAssetTypeVideo])
                requestedAssetInfo[APAssetType] = APAssetTypeVideo;
            
            requestedAssetInfo[APAssetContentsURL] = fileURL;
            
            [requestedAssets addObject:requestedAssetInfo];
        });
    }
}

-(void)updateProgress
{
    progressBar.progress = (float)totalBytesWritten / totalBytesToWrite;
    //APLog(@"progress -> %f", progressBar.progress);
    
    if(progressBar.progress == 1.0f)
    {
        double delayInSeconds = 0.5f;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [loadingShield removeFromSuperview];
            [self.navigationController popViewControllerAnimated:YES];
            [self removeTopBarNClearViewProvideNavigationBarOriginalAppearance];
            
            if(apCompletion != nil)
            {
                apCompletion(self,requestedAssets);
                apCompletion = nil;
            }
        });
    }
}

#pragma mark
#pragma mark<Loading>
#pragma mark

-(void)prepareLoading
{
    loadingShield = [[UIView alloc] initWithFrame:ScreenBounds];
    loadingShield.backgroundColor = [UIColor clearColor];
    
    loadingImgVw = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    loadingImgVw.center = loadingShield.center;
    loadingImgVw.image = Image(@"ap_loading.png");
    
    [loadingShield addSubview:loadingImgVw];
}

-(void)showLoading
{
    if([loadingShield superview] == nil)
    {
        [self.navigationController.view addSubview:loadingShield];
        
        CAKeyframeAnimation* animateTransform =
        [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        animateTransform.duration = 0.75f;
        animateTransform.repeatCount = CGFLOAT_MAX;
        animateTransform.values =
        @[[NSValue valueWithCATransform3D:CATransform3DMakeRotation(0, 0, 0, 1)],
          [NSValue valueWithCATransform3D:CATransform3DMakeRotation(M_PI*0.99, 0, 0, 1)]];
        animateTransform.keyTimes = @[@0.0,@1.0];
        [loadingImgVw.layer addAnimation:animateTransform forKey:nil];
    }
}

-(void)stopLoading
{
    if([loadingShield superview] != nil)
    {
        [loadingImgVw.layer removeAllAnimations];
        [loadingShield performSelector:@selector(removeFromSuperview)
                            withObject:nil afterDelay:0.1];
    }
}

#pragma mark
#pragma mark<Camera Options>
#pragma mark

-(void)showCameraOptions
{
    if(cameraOptionsContainer == nil)
    {
        CGFloat topBarHeight = topBar.frame.size.height;
        CGFloat yOffset = StatusBarHeight+topBarHeight-9+(topBarHeight==32?6:0);
        
        cameraOptionsContainer =
        [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMidX(cameraBtn.frame)-170,
                                                 yOffset, 200, 218)];
        cameraOptionsContainer.backgroundColor = [UIColor clearColor];
        
        UIImageView* topArrowImgVw = [[UIImageView alloc]
                                      initWithFrame:CGRectMake(160, 0, 20, 20)];
        topArrowImgVw.image = Image(@"ap_up_arrow.png");
        [cameraOptionsContainer addSubview:topArrowImgVw];
        
        UIView* cameraOptionsVw = [[UIView alloc] initWithFrame:CGRectMake(0, 18, 200, 200)];
        cameraOptionsVw.backgroundColor = [UIColor whiteColor];
        cameraOptionsVw.layer.cornerRadius = 8.0f;
        
        cameraDevice = UIImagePickerControllerCameraDeviceRear;
        cameraQuality = UIImagePickerControllerQualityTypeHigh;
        cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;
        cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
        
        NSArray* defaultOptions = @[@"Type - REAR", @"Quality - HIGH",
                                    @"Flash - OFF", @"Mode - PHOTO"];
        
        yOffset = 5;
        for(int i=1; i<5; i++)
        {
            UIButton* pointerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            pointerBtn.frame = CGRectMake(5, yOffset, 42, 30);
            [pointerBtn setImage:Image(@"ap_pointer.png") forState:UIControlStateNormal];
            [pointerBtn setImageEdgeInsets:UIEdgeInsetsMake(5, 5, 5, 5)];
            [pointerBtn addTarget:self action:@selector(pointerTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
            pointerBtn.tag = (i*1000)+1;
            
            UILabel* cameraOptionLbl = [[UILabel alloc]
                                        initWithFrame:CGRectMake(55, yOffset, 140, 30)];
            cameraOptionLbl.backgroundColor = [UIColor clearColor];
            cameraOptionLbl.font = FontWithSize(16.0f);
            cameraOptionLbl.textAlignment = NSTextAlignmentLeft;
            cameraOptionLbl.textColor = [UIColor blackColor];
            cameraOptionLbl.tag = (i*1000)+2;
            
            [cameraOptionsVw addSubview:pointerBtn];
            [cameraOptionsVw addSubview:cameraOptionLbl];
            
            yOffset += 40;
            
            cameraOptionLbl.text = defaultOptions[i-1];
        }
        
        UIButton* takeAShotBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        takeAShotBtn.frame = CGRectMake(85, 165, 30, 30);
        [takeAShotBtn setImage:Image(@"ap_take_a_shot.png") forState:UIControlStateNormal];
        [takeAShotBtn addTarget:self action:@selector(openCamera:)
               forControlEvents:UIControlEventTouchUpInside];
        [cameraOptionsVw addSubview:takeAShotBtn];
        
        cameraOptionsContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        cameraOptionsContainer.layer.shadowOffset = CGSizeMake(1, 1);
        cameraOptionsContainer.layer.shadowOpacity = 1.0f;
        
        [cameraOptionsContainer addSubview:cameraOptionsVw];
        [cameraOptionsContainer bringSubviewToFront:topArrowImgVw];
    }
    
    if([cameraOptionsContainer superview] == nil)
    {
        [self.navigationController.view bringSubviewToFront:clearViewForDisablingUI];
        [self.navigationController.view addSubview:cameraOptionsContainer];
    }
}

-(void)pointerTapped:(UIButton*)sender
{
    UILabel* targetLbl = (UILabel*)[sender.superview viewWithTag:sender.tag+1];
    
    [UIView animateWithDuration:0.5f delay:0.0f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^
     {
         sender.layer.transform = CATransform3DRotate(sender.layer.transform, M_PI, 0, 1, 0);
         sender.layer.transform = CATransform3DMakeRotation(0, 0, 1, 0);
     }
                     completion:
     ^(BOOL finished)
     {
         switch(sender.tag/1000)
         {
             case 1:
             {
                 NSString* typeStr = @"";
                 if(cameraDevice == UIImagePickerControllerCameraDeviceRear)
                 {
                     cameraDevice = UIImagePickerControllerCameraDeviceFront;
                     typeStr = @"FRONT";
                 }
                 else if(cameraDevice == UIImagePickerControllerCameraDeviceFront)
                 {
                     cameraDevice = UIImagePickerControllerCameraDeviceRear;
                     typeStr = @"REAR";
                 }
                 
                 targetLbl.text = [NSString stringWithFormat:@"Type - %@",typeStr];
             }
                 break;
                 
             case 2:
             {
                 NSString* qualityStr = @"";
                 if(cameraQuality == UIImagePickerControllerQualityTypeHigh)
                 {
                     cameraQuality = UIImagePickerControllerQualityTypeMedium;
                     qualityStr = @"MEDIUM";
                 }
                 else if(cameraQuality == UIImagePickerControllerQualityTypeMedium)
                 {
                     cameraQuality = UIImagePickerControllerQualityTypeLow;
                     qualityStr = @"LOW";
                 }
                 else if(cameraQuality == UIImagePickerControllerQualityTypeLow)
                 {
                     cameraQuality = UIImagePickerControllerQualityTypeHigh;
                     qualityStr = @"HIGH";
                 }
                 
                 targetLbl.text = [NSString stringWithFormat:@"Quality - %@",qualityStr];
             }
                 break;
                 
             case 3:
             {
                 NSString* flashStr = @"";
                 if(cameraFlashMode == UIImagePickerControllerCameraFlashModeAuto)
                 {
                     cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;
                     flashStr = @"OFF";
                 }
                 else if(cameraFlashMode == UIImagePickerControllerCameraFlashModeOff)
                 {
                     cameraFlashMode = UIImagePickerControllerCameraFlashModeOn;
                     flashStr = @"ON";
                 }
                 else if(cameraFlashMode == UIImagePickerControllerCameraFlashModeOn)
                 {
                     cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
                     flashStr = @"AUTO";
                 }
                 
                 targetLbl.text = [NSString stringWithFormat:@"Flash - %@",flashStr];
             }
                 break;
                 
             case 4:
             {
                 NSString* modeStr = @"";
                 if(cameraCaptureMode == UIImagePickerControllerCameraCaptureModePhoto)
                 {
                     cameraCaptureMode = UIImagePickerControllerCameraCaptureModeVideo;
                     modeStr = @"VIDEO";
                 }
                 else if(cameraCaptureMode == UIImagePickerControllerCameraCaptureModeVideo)
                 {
                     cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
                     modeStr = @"PHOTO";
                 }
                 
                 targetLbl.text = [NSString stringWithFormat:@"Mode - %@",modeStr];
             }
                 break;
                 
             default:
                 break;
         }
     }];
}

-(void)openCamera:(UIButton*)sender
{
    [self.navigationController.view sendSubviewToBack:clearViewForDisablingUI];
    [cameraOptionsContainer removeFromSuperview];
    
    if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
    {
        UIImagePickerController* cameraController = [[UIImagePickerController alloc] init];
        cameraController.sourceType = UIImagePickerControllerSourceTypeCamera;
        cameraController.mediaTypes =
        [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
        cameraController.cameraDevice = cameraDevice;
        cameraController.videoQuality = cameraQuality;
        cameraController.cameraFlashMode = cameraFlashMode;
        cameraController.cameraCaptureMode = cameraCaptureMode;
        
        cameraController.delegate = self;
        [self presentViewController:cameraController animated:YES completion:nil];
    }
    else
    {
        NSString* message =
        @"This device doesn't have camera support. "
        "To use this feature, use this on a device with camera support.";
        
        [[[UIAlertView alloc] initWithTitle:@"Camera Not Available!"
                                    message:message
                                   delegate:nil
                          cancelButtonTitle:@"Okay"
                          otherButtonTitles:nil] show];
    }
}

#pragma mark
#pragma mark<UIImagePickerControllerDelegate Methods>
#pragma mark

-(void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    [Application setNetworkActivityIndicatorVisible:YES];
    dispatch_async(assetWriteQueue, ^{
        if([info[UIImagePickerControllerMediaType] isEqualToString:@"public.image"])
        {
            UIImage* originalImage = info[UIImagePickerControllerOriginalImage];
            ALAssetOrientation orientation = (ALAssetOrientation)originalImage.imageOrientation;
            [AssetsLibrary writeImageToSavedPhotosAlbum:originalImage.CGImage
                                            orientation:orientation
                                        completionBlock:^(NSURL* assetURL, NSError* error)
             {
                 [Application setNetworkActivityIndicatorVisible:NO];
                 
                 if(error != nil)
                 {
                     APLog(@"Couldn't Save Image. Reason :- %@", error.localizedDescription);
                     return;
                 }
                 
                 dispatch_async(dispatch_get_main_queue(), ^{
                     [self refreshSavedPhotosAddAssetWithURL:assetURL];
                 });
             }];
        }
        else
        {
            NSURL* videoURL = info[UIImagePickerControllerMediaURL];
            if([AssetsLibrary videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL])
            {
                [AssetsLibrary writeVideoAtPathToSavedPhotosAlbum:videoURL
                                                  completionBlock:^(NSURL* assetURL, NSError* error)
                 {
                     [Application setNetworkActivityIndicatorVisible:NO];
                     
                     if(error != nil)
                     {
                         APLog(@"Couldn't Save Video. Reason :- %@", error.localizedDescription);
                         return;
                     }
                     
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self refreshSavedPhotosAddAssetWithURL:assetURL];
                     });
                 }];
            }
        }
    });
}

-(void)imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark
#pragma mark<UICollectionViewDataSource Methods>
#pragma mark

-(NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)collectionView
{
    NSInteger noOfSections = 0;
    if([availableAssets count] > 0)
        noOfSections = [availableAssets count];
    
    return noOfSections;
}

-(NSInteger)collectionView:(UICollectionView*)collectionView
    numberOfItemsInSection:(NSInteger)section
{
    NSInteger noOfItems = 0;
    if([availableAssets[section] count] > 0)
        noOfItems = [availableAssets[section][AlbumAssets] count];
    
    return noOfItems;
}

-(UICollectionViewCell*)collectionView:(UICollectionView*)collectionView
                cellForItemAtIndexPath:(NSIndexPath*)indexPath
{
    APAvailableAssetsCollectionItem* cell = (APAvailableAssetsCollectionItem*)
    [collectionView dequeueReusableCellWithReuseIdentifier:AvailableAssetsCollectionItem
                                              forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    
    UIImageView* imgVw = (UIImageView*)[cell.contentView viewWithTag:11111];
    UIView* videoInfoVw = [cell.contentView viewWithTag:22222];
    UILabel* durationLbl = (UILabel*)[videoInfoVw viewWithTag:33333];
    
    CGFloat cellSize = cell.bounds.size.width;
    CGFloat bannerHeight = IsPad?20:15;
    
    if(imgVw == nil)
    {
        imgVw = [[UIImageView alloc] initWithFrame:cell.bounds];
        imgVw.contentMode = UIViewContentModeScaleAspectFit;
        imgVw.backgroundColor = [UIColor clearColor];
        imgVw.tag = 11111;
        
        videoInfoVw = [[UIView alloc] initWithFrame:
                       CGRectMake(0, cellSize-bannerHeight, cellSize, bannerHeight)];
        videoInfoVw.backgroundColor = [UIColor clearColor];
        videoInfoVw.tag = 22222;
        
        CAGradientLayer* layer = [CAGradientLayer layer];
        layer.colors = @[(__bridge UIColor*)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                         (__bridge UIColor*)[UIColor blackColor].CGColor];
        layer.frame = videoInfoVw.bounds;
        [videoInfoVw.layer addSublayer:layer];
        
        UIImageView* videoIconImgVw = [[UIImageView alloc] initWithFrame:
                                       CGRectMake(5, 2, bannerHeight-5, bannerHeight-5)];
        videoIconImgVw.image = Image(@"ap_play.png");
        [videoInfoVw addSubview:videoIconImgVw];
        
        durationLbl = [[UILabel alloc] initWithFrame:
                       CGRectMake(bannerHeight+5, 0, cellSize-(bannerHeight+10), bannerHeight)];
        durationLbl.backgroundColor = [UIColor clearColor];
        durationLbl.textAlignment = NSTextAlignmentRight;
        durationLbl.textColor = [UIColor whiteColor];
        durationLbl.font = FontWithSize(IsPad?12.0f:10.0f);
        [videoInfoVw addSubview:durationLbl];
        durationLbl.tag = 33333;
        
        [cell.contentView addSubview:imgVw];
        [cell.contentView addSubview:videoInfoVw];
    }
    
    ALAsset* asset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    if(asset != nil)
    {
        [cell setSelected:[selectedAssets containsAsset:asset]];
        
        UIImage* image = [UIImage imageWithCGImage:
                          (IsPad? [asset aspectRatioThumbnail] : [asset thumbnail])];
        imgVw.image = image;
        
        if(IsPad)
        {
            float fitImageWidth = 0.0f;
            float fitImageHeight = 0.0f;
            if(image.size.width < image.size.height)
            {
                fitImageWidth = image.size.width * cellSize/image.size.height;
                fitImageHeight = image.size.height * fitImageWidth/image.size.width;
            }
            else
            {
                fitImageHeight = image.size.height * cellSize/image.size.width;
                fitImageWidth = image.size.width * fitImageHeight/image.size.height;
            }
            
            CGFloat iconSize = IsPad?20:14;
            cell.selectedCheckIcon.frame = CGRectMake(((cellSize-fitImageWidth)/2)+2,
                                                      ((cellSize-fitImageHeight)/2)+2,
                                                      iconSize, iconSize);
            
            videoInfoVw.frame = CGRectMake(0, cellSize-((cellSize-fitImageHeight)/2)-bannerHeight,
                                           cellSize, bannerHeight);
        }
        
        if([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
        {
            videoInfoVw.hidden = NO;
            cell.type = APCollectionCellTypeVideo;
            
            NSInteger duration = ceil([[asset valueForProperty:
                                        ALAssetPropertyDuration] doubleValue]);
            NSInteger hrs = duration/3600;
            NSInteger mins = (duration%3600)/60;
            NSInteger secs = (duration%3600)%60;
            if(hrs > 0)
                durationLbl.text = [NSString stringWithFormat:@"%d:%02d:%02d",hrs,mins,secs];
            else
                durationLbl.text = [NSString stringWithFormat:@"%d:%02d",mins,secs];
        }
        else
        {
            videoInfoVw.hidden = YES;
            cell.type = APCollectionCellTypePhoto;
        }
    }
    
    return cell;
}

-(UICollectionReusableView*)collectionView:(UICollectionView*)collectionView
         viewForSupplementaryElementOfKind:(NSString*)kind
                               atIndexPath:(NSIndexPath*)indexPath
{
    UICollectionReusableView* headerVw =
    [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                       withReuseIdentifier:AvailableAssetsCollectionHeader
                                              forIndexPath:indexPath];
    headerVw.backgroundColor = UIColorWithRGBA(236, 236, 236, 1);
    
    UILabel* albumNameLbl = (UILabel*)[headerVw viewWithTag:12345];
    if(albumNameLbl == nil)
    {
        albumNameLbl = [[UILabel alloc] initWithFrame:
                        CGRectInset(headerVw.bounds, 10, IsPad?5:2)];
        albumNameLbl.backgroundColor = [UIColor clearColor];
        albumNameLbl.textAlignment = NSTextAlignmentLeft;
        albumNameLbl.textColor = UIColorWithRGBA(70, 70, 70, 1);
        albumNameLbl.font = FontWithSize(14.0f);
        albumNameLbl.adjustsFontSizeToFitWidth = YES;
        albumNameLbl.minimumScaleFactor = 0.75f;
        [headerVw addSubview:albumNameLbl];
        albumNameLbl.tag = 12345;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshSectionHeader:headerVw forIndexPath:indexPath];
    });
    
    sectionHeaders[indexPath] = headerVw;
    
    return headerVw;
}

#pragma mark
#pragma mark<UICollectionViewDelegate Methods>
#pragma mark

-(void)collectionViewCellTapped:(NSNotification*)notification
{
    APAvailableAssetsCollectionItem* item = (APAvailableAssetsCollectionItem*)notification.object;
    NSIndexPath* indexPath = [availableAssetsClctnVw indexPathForCell:item];
    ALAsset* asset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    
    if(item.selected)
        [selectedAssets addAsset:asset];
    else
        [selectedAssets removeAsset:asset];
    
    [self reloadSectionHeadersAndAnyVisibleMatchingItemUsingIndexPath:indexPath];
}

-(void)collectionView:(UICollectionView*)collectionView didEndDisplayingSupplementaryView:(UICollectionReusableView*)view forElementOfKind:(NSString*)elementKind atIndexPath:(NSIndexPath*)indexPath
{
    [sectionHeaders removeObjectForKey:indexPath];
}

@end
