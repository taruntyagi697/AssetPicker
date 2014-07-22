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

#define UIColorWithRGBA(r,g,b,a) \
[UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]

#define Image(i) [UIImage imageNamed:i]

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
#define ChunkSize    (1024*1024)

#define AssetInfoLoadQueue @"AssetInfoLoadQueue"
#define AssetWriteQueue    @"AssetWriteQueue"

#define AssetWriteDirectoryPath \
[NSHomeDirectory() stringByAppendingFormat:@"/Documents/AssetPickerTemp"]

#define CameraReturnedAssetWritten @"CameraReturnedAssetWritten"

// External Variables' DEFINITIONS
const NSString* APOriginalAsset = @"APOriginalAsset";
const NSString* APAssetContentsURL = @"APAssetContentsURL";

const NSString* APAssetType = @"APAssetType";
const NSString* APAssetTypePhoto = @"APAssetTypePhoto";
const NSString* APAssetTypeVideo = @"APAssetTypeVideo";

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

@interface APAvailableAssetsCollectionItem : UICollectionViewCell
{
    UIImageView* selectedCheckIcon;
}
@end

@implementation APAvailableAssetsCollectionItem

-(id)initWithFrame:(CGRect)frame
{
    if(self = [super initWithFrame:frame])
    {
        CGFloat iconSize = IsPad?30:20;
        selectedCheckIcon = [[UIImageView alloc] initWithFrame:
                             CGRectMake(0, 0, iconSize, iconSize)];
        selectedCheckIcon.image = Image(@"ap_check.png");
        [self addSubview:selectedCheckIcon];
        
        selectedCheckIcon.hidden = YES;
        
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
    self.selected = !self.selected;
    [NotificationCenter postNotificationName:ItemTappedNotification object:self];
}

-(void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    
    if(selected)
    {
        selectedCheckIcon.hidden = NO;
        self.alpha = 0.5f;
    }
    else
    {
        selectedCheckIcon.hidden = YES;
        self.alpha = 1.0f;
    }
}

-(void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    
    self.alpha = highlighted ? 0.5f : 1.0f;
    selectedCheckIcon.hidden = YES;
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
    
    // Remember if we forced the StatusBar/NavigationBar to hide on opening
    BOOL forcedStatusBarToHide;
    BOOL forcedNavigationBarToHide;
    
    // TopBar
    UIView* topBar;
    
    // TopBar - Filter Options
    APFilterType filterType;
    
    // TopBar - Camera Options
    UIView* cameraOptionsContainer;
    UIImagePickerControllerCameraDevice cameraDevice;
    UIImagePickerControllerQualityType cameraQuality;
    UIImagePickerControllerCameraFlashMode cameraFlashMode;
    UIImagePickerControllerCameraCaptureMode cameraCaptureMode;
    CGFloat cameraHorizontalMidX;
    
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
    AssetPicker* picker = [[AssetPicker alloc] initWithCompletionHandler:completion
                                                           cancelHandler:cancel];
    [navigationController pushViewController:picker animated:YES];
}

-(id)initWithCompletionHandler:(APCompletionHandler)completion
                 cancelHandler:(APCancelHandler)cancel
{
    if(self = [super init])
    {
        apCompletion = completion;
        apCancel = cancel;
        
        storedAssets = [@[] mutableCopy];
        availableAssets = [@[] mutableCopy];
        
        selectedAssets = [@[] mutableCopy];
    }
    
    return self;
}

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
    self.view.backgroundColor = UIColorWithRGBA(230, 230, 230, 1);
    self.navigationController.delegate = self;
    
    [self checkStatusBarHidePermission];
    
    // Prepare clearView and send it below all others
    clearViewForDisablingUI = [[UIView alloc] initWithFrame:ScreenBounds];
    clearViewForDisablingUI.backgroundColor = [UIColor clearColor];
    [self.view addSubview:clearViewForDisablingUI];
    [self.view sendSubviewToBack:clearViewForDisablingUI];
    
    // By Default, filter is PHOTOS
    filterType = APFilterTypePhotos;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepareTopBar];
        [self prepareLoading];
    });
    
    [self fetchAvailableAssets];
    
    assetWriteQueue = dispatch_queue_create([AssetWriteQueue UTF8String], NULL);
}

-(void)checkStatusBarHidePermission
{
    if(iOSVersion >= 7.0f)
    {
        NSDictionary* infoPlistDict = [[NSBundle mainBundle] infoDictionary];
        NSNumber* statusBarPermission = infoPlistDict[@"UIViewControllerBasedStatusBarAppearance"];
        if(statusBarPermission == nil || [statusBarPermission boolValue])
        {
            APLog(@"StatusBar could't be forced to hide. Permission Not Set.\n"
                  "To do this, add 'View controller-based status bar appearance = NO' "
                  "in your project's info plist.\n"
                  "Raw key for this is 'UIViewControllerBasedStatusBarAppearance'");
        }
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    if(!self.navigationController.navigationBarHidden)
    {
        forcedNavigationBarToHide = YES;
        [self.navigationController setNavigationBarHidden:YES animated:YES];
    }
    
    [NotificationCenter addObserver:self
                           selector:@selector(collectionViewCellTapped:)
                               name:ItemTappedNotification
                             object:nil];
}

-(void)viewDidDisappear:(BOOL)animated
{
    if(forcedStatusBarToHide)
        [Application setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    
    if(forcedNavigationBarToHide)
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    
    [NotificationCenter removeObserver:self];
}

#pragma mark
#pragma mark<UINavigationControllerDelegate>
#pragma mark

-(void)navigationController:(UINavigationController*)navigationController
     willShowViewController:(UIViewController*)viewController animated:(BOOL)animated
{
    forcedStatusBarToHide = !CGRectEqualToRect([Application statusBarFrame],CGRectZero);
    [Application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}

#pragma mark
#pragma mark<Helpers>
#pragma mark

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
                 
                 if([albumName isEqualToString:@"Saved Photos"])
                     [storedAssets insertObject:albumInfo atIndex:0];
                 else
                     [storedAssets addObject:albumInfo];
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
         }];
    });
}

-(void)addAvailableAssetsCollectionView
{
    CGFloat size = IsPad?140:96;
    CGFloat padding = 10;
    
    UICollectionViewFlowLayout* layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = IsPad?10:6;
    layout.minimumInteritemSpacing = 0;
    layout.itemSize = CGSizeMake(size, size);
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.headerReferenceSize = CGSizeMake(ScreenWidth, IsPad?35:25);
    layout.footerReferenceSize = CGSizeZero;
    layout.sectionInset = UIEdgeInsetsMake(padding, padding, padding, padding);
    
    availableAssetsClctnVw =
    [[UICollectionView alloc]
     initWithFrame:CGRectMake(0, 44, ScreenWidth, ScreenHeight-44)
     collectionViewLayout:layout];
    availableAssetsClctnVw.dataSource = self;
    availableAssetsClctnVw.delegate = self;
    availableAssetsClctnVw.allowsMultipleSelection = YES;
    availableAssetsClctnVw.backgroundColor = [UIColor clearColor];
    [self.view addSubview:availableAssetsClctnVw];
    
    [availableAssetsClctnVw registerClass:[APAvailableAssetsCollectionItem class]
               forCellWithReuseIdentifier:AvailableAssetsCollectionItem];
    
    [availableAssetsClctnVw registerClass:[UICollectionReusableView class]
               forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                      withReuseIdentifier:AvailableAssetsCollectionHeader];
    
    availableAssets = [self filteredAssets];
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
        NSMutableArray* albumAssets = storedAlbumInfo[AlbumAssets];
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
    NSArray* albumAssets = albumInfo[AlbumAssets];
    
    NSInteger filteredMatches = 0;
    for(ALAsset* selAsset in selectedAssets) {
        for(ALAsset* albumAsset in albumAssets) {
            if([selAsset isEqualToAsset:albumAsset]) {
                filteredMatches++;
                break;
            }
        }
    }
    
    NSInteger totalMatches = 0;
    if(filterType == APFilterTypeAll) {
        totalMatches = filteredMatches;
    } else {
        NSMutableArray* storedAlbumAssets = storedAssets[indexPath.section][AlbumAssets];
        for(ALAsset* selAsset in selectedAssets) {
            for(ALAsset* albumAsset in storedAlbumAssets) {
                if([selAsset isEqualToAsset:albumAsset]) {
                    totalMatches++;
                    break;
                }
            }
        }
    }
    
    UILabel* albumNameLbl = (UILabel*)[headerVw viewWithTag:12345];
    albumNameLbl.text = [NSString stringWithFormat:
                         @"%@ (%d) - %d Selected - Total %d Selected",
                         albumInfo[AlbumName], [albumInfo[AlbumAssets] count],
                         filteredMatches, totalMatches];
}

-(void)reloadSectionHeadersAndAnyVisibleMatchingItemUsingIndexPath:(NSIndexPath*)indexPath
{
    [sectionHeaders enumerateKeysAndObjectsUsingBlock:
     ^(NSIndexPath* key, UIView* obj, BOOL *stop)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             [self refreshSectionHeader:obj forIndexPath:key];
         });
     }];
    
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

-(void)refreshSavedPhotosAlbumAssets
{
    [AssetsLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                 usingBlock:^(ALAssetsGroup* group, BOOL* stop)
     {
         if(group != nil)
         {
             if([group numberOfAssets] > [storedAssets[0][AlbumAssets] count])
             {
                 [group enumerateAssetsWithOptions:NSEnumerationReverse
                                        usingBlock:^(ALAsset* result, NSUInteger index, BOOL* stop)
                  {
                      if(result != nil)
                      {
                          *stop = YES;
                          [selectedAssets addAsset:result];
                          [storedAssets[0][AlbumAssets] addObject:result];
                          
                          NSString* assetType = [result valueForProperty:ALAssetPropertyType];
                          
                          if((filterType == APFilterTypeAll) ||
                             ([assetType isEqualToString:ALAssetTypePhoto] && filterType == APFilterTypePhotos) ||
                             ([assetType isEqualToString:ALAssetTypeVideo] && filterType == APFilterTypeVideos))
                          {
                              [availableAssets[0][AlbumAssets] addObject:result];
                              
                              NSIndexPath* indexPath =
                              [NSIndexPath indexPathForItem:[availableAssets[0][AlbumAssets] count]-1 inSection:0];
                              [availableAssetsClctnVw insertItemsAtIndexPaths:@[indexPath]];
                              
                              double delayInSeconds = 0.75f;
                              dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                              dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                                  APAvailableAssetsCollectionItem* item = (APAvailableAssetsCollectionItem*)
                                  [availableAssetsClctnVw cellForItemAtIndexPath:indexPath];
                                  item.selected = YES;
                                  [NotificationCenter postNotificationName:ItemTappedNotification object:item];
                              });
                          }
                      }
                  }];
             }
             else
             {
                 [self performSelector:_cmd withObject:nil afterDelay:2.0f];
             }
         }
     }
                               failureBlock:^(NSError* error)
     {
         APLog(@"AssetLibrary Group 'SavedPhotos' couldn't be browsed at the time."
               " Reason :- %@", error.localizedDescription);
     }];
}

#pragma mark
#pragma mark<UIResponder Methods>
#pragma mark

-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    if([[[touches anyObject] view] isEqual:clearViewForDisablingUI])
    {
        [self.view sendSubviewToBack:clearViewForDisablingUI];
        [cameraOptionsContainer removeFromSuperview];
    }
}

#pragma mark
#pragma mark<TopBar>
#pragma mark

-(void)prepareTopBar
{
    topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, 44)];
    topBar.backgroundColor = [UIColor lightGrayColor];
    
    UIButton* backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.imageEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 14);
    backBtn.backgroundColor = [UIColor clearColor];
    [backBtn setImage:Image(@"ap_back.png") forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(backBtnAction:)
      forControlEvents:UIControlEventTouchUpInside];
    
    UIButton* filterBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [filterBtn setImage:Image(@"ap_photo.png") forState:UIControlStateNormal];
    [filterBtn addTarget:self action:@selector(filterBtnAction:)
        forControlEvents:UIControlEventTouchUpInside];
    
    UILabel* titleLbl = [[UILabel alloc] init];
    titleLbl.backgroundColor = [UIColor clearColor];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.textColor = UIColorWithRGBA(38, 38, 38, 1);
    titleLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:16.0f];
    titleLbl.numberOfLines = 0;
    
    UIButton* cameraBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [cameraBtn setImage:Image(@"ap_camera.png") forState:UIControlStateNormal];
    [cameraBtn addTarget:self action:@selector(cameraBtnAction:)
        forControlEvents:UIControlEventTouchUpInside];
    
    UIButton* doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [doneBtn setImage:Image(@"ap_done.png") forState:UIControlStateNormal];
    [doneBtn addTarget:self action:@selector(doneBtnAction:)
      forControlEvents:UIControlEventTouchUpInside];
    
    CGFloat titleLblWidth = (IsPad?400:(IsPortrait?170:300));
    
    backBtn.frame = CGRectMake((IsPad?3:0), 7, 36, 30);
    filterBtn.frame = CGRectMake((IsPad?60:40), 7, 30, 30);
    titleLbl.frame = CGRectMake((ScreenWidth-titleLblWidth)/2, 3, titleLblWidth, 38);
    cameraBtn.frame = CGRectMake((ScreenWidth-(IsPad?90:(IsPortrait?71:80))), 7, 30, 30);
    doneBtn.frame = CGRectMake((ScreenWidth-(IsPad?40:(IsPortrait?34:40))), 7, 33, 30);
    
    cameraHorizontalMidX = CGRectGetMidX(cameraBtn.frame);
    
    [topBar addSubview:backBtn];
    [topBar addSubview:filterBtn];
    [topBar addSubview:titleLbl];
    [topBar addSubview:cameraBtn];
    [topBar addSubview:doneBtn];
    
    [self.view addSubview:topBar];
    titleLbl.text = @"Select Photos/Videos From Library";
}

-(void)backBtnAction:(UIButton*)sender
{
    [self.navigationController popViewControllerAnimated:YES];
    
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
        
        if(apCompletion != nil)
        {
            apCompletion(self, @[]);
            apCompletion = nil;
        }
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
    writingFilesMessageLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:16.0f];
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
                Byte* buffer = malloc(ChunkSize);
                
                NSInteger bytesRead = [representation getBytes:buffer fromOffset:offset
                                                        length:ChunkSize error:nil];
                NSData* data = [NSData dataWithBytesNoCopy:buffer length:bytesRead];
                [fileHandle writeData:data];
                
                offset += bytesRead;
                free(buffer);
                
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
            [writingFilesMessageLbl removeFromSuperview];
            [progressBar removeFromSuperview];
            
            [self.navigationController popViewControllerAnimated:YES];
            
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
    loadingShield = [[UIView alloc] initWithFrame:self.view.bounds];
    loadingShield.backgroundColor = [UIColor clearColor];
    
    loadingImgVw = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    loadingImgVw.center = loadingShield.center;
    loadingImgVw.image = [UIImage imageNamed:@"ap_loading.png"];
    
    [loadingShield addSubview:loadingImgVw];
}

-(void)showLoading
{
    if([loadingShield superview] == nil)
    {
        [self.view addSubview:loadingShield];
        
        CAKeyframeAnimation* animateTransform =
        [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        animateTransform.duration = 0.75f;
        animateTransform.repeatCount = CGFLOAT_MAX;
        animateTransform.values =
        @[[NSValue valueWithCATransform3D:CATransform3DMakeRotation(0, 0, 0, 1)],
          [NSValue valueWithCATransform3D:CATransform3DMakeRotation(M_PI*0.99, 0, 0, 1)]];
        animateTransform.keyTimes = @[@0.0,@1.0];
        [loadingImgVw.layer addAnimation:animateTransform forKey:nil];
        
        /*[UIView animateWithDuration:0.75
                              delay:0.0
                            options:UIViewAnimationOptionRepeat
                         animations:
         ^{loadingImgVw.transform = CGAffineTransformRotate(loadingImgVw.transform, M_PI*0.99);}
                         completion:
         ^(BOOL finished){}];*/
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
        cameraOptionsContainer = [[UIView alloc]
                                  initWithFrame:CGRectMake(cameraHorizontalMidX-170, 35, 200, 258)];
        cameraOptionsContainer.backgroundColor = [UIColor clearColor];
        
        UIImageView* topArrowImgVw = [[UIImageView alloc]
                                      initWithFrame:CGRectMake(160, 0, 20, 20)];
        topArrowImgVw.image = [UIImage imageNamed:@"ap_up_arrow.png"];
        [cameraOptionsContainer addSubview:topArrowImgVw];
        
        UIView* cameraOptionsVw = [[UIView alloc] initWithFrame:CGRectMake(0, 18, 200, 240)];
        cameraOptionsVw.backgroundColor = [UIColor whiteColor];
        cameraOptionsVw.layer.cornerRadius = 8.0f;
        
        cameraDevice = UIImagePickerControllerCameraDeviceRear;
        cameraQuality = UIImagePickerControllerQualityTypeHigh;
        cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;
        cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
        
        NSArray* defaultOptions = @[@"Type - REAR", @"Quality - HIGH",
                                    @"Flash - OFF", @"Mode - PHOTO"];
        
        CGFloat yOffset = 20;
        for(int i=1; i<5; i++)
        {
            UIButton* pointerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            pointerBtn.frame = CGRectMake(5, yOffset, 42, 30);
            [pointerBtn setImage:Image(@"ap_pointer.png") forState:UIControlStateNormal];
            [pointerBtn addTarget:self action:@selector(pointerTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
            pointerBtn.tag = (i*1000)+1;
            
            UILabel* cameraOptionLbl = [[UILabel alloc]
                                        initWithFrame:CGRectMake(55, yOffset, 140, 30)];
            cameraOptionLbl.backgroundColor = [UIColor clearColor];
            cameraOptionLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:16.0f];
            cameraOptionLbl.textAlignment = NSTextAlignmentLeft;
            cameraOptionLbl.textColor = [UIColor blackColor];
            cameraOptionLbl.tag = (i*1000)+2;
            
            [cameraOptionsVw addSubview:pointerBtn];
            [cameraOptionsVw addSubview:cameraOptionLbl];
            
            yOffset += 40;
            
            cameraOptionLbl.text = defaultOptions[i-1];
        }
        
        UIButton* takeAShotBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        takeAShotBtn.frame = CGRectMake(85, 190, 30, 30);
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
        [self.view bringSubviewToFront:clearViewForDisablingUI];
        [self.view addSubview:cameraOptionsContainer];
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
    [self.view sendSubviewToBack:clearViewForDisablingUI];
    [cameraOptionsContainer removeFromSuperview];
    
    if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
    {
        UIImagePickerController* cameraController = [[UIImagePickerController alloc] init];
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
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if([info[UIImagePickerControllerMediaType] isEqualToString:@"public.image"])
        {
            UIImageWriteToSavedPhotosAlbum(info[UIImagePickerControllerOriginalImage],
                                           self, @selector(refreshSavedPhotosAlbumAssets),
                                           CameraReturnedAssetWritten);
        }
        else
        {
            NSString* videoPath = ((NSURL*)info[UIImagePickerControllerMediaURL]).path;
            if(UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(videoPath))
            {
                UISaveVideoAtPathToSavedPhotosAlbum(videoPath, self,
                                                    @selector(refreshSavedPhotosAlbumAssets),
                                                    CameraReturnedAssetWritten);
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
    UILabel* nameLbl = (UILabel*)[cell.contentView viewWithTag:22222];
    UIView* videoInfoVw = [cell.contentView viewWithTag:33333];
    UILabel* durationLbl = (UILabel*)[videoInfoVw viewWithTag:44444];
    
    if(imgVw == nil)
    {
        imgVw = [[UIImageView alloc] initWithFrame:cell.bounds];
        imgVw.contentMode = UIViewContentModeScaleAspectFit;
        imgVw.backgroundColor = [UIColor clearColor];
        imgVw.tag = 11111;
        
        CGFloat cellSize = cell.bounds.size.width;
        CGFloat bannerHeight = IsPad?20:15;
        
        nameLbl = [[UILabel alloc] initWithFrame:
                   CGRectMake(0, cellSize-bannerHeight, cellSize, bannerHeight)];
        nameLbl.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
        nameLbl.textAlignment = NSTextAlignmentCenter;
        nameLbl.textColor = [UIColor darkGrayColor];
        nameLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:IsPad?12:10];
        nameLbl.tag = 22222;
        
        videoInfoVw = [[UIView alloc] initWithFrame:
                       CGRectMake(0, cellSize-2*bannerHeight, cellSize, bannerHeight)];
        videoInfoVw.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
        videoInfoVw.tag = 33333;
        
        UIImageView* videoIconImgVw = [[UIImageView alloc] initWithFrame:
                                       CGRectMake(2, IsPad?2:1, IsPad?22:17, IsPad?16:12)];
        videoIconImgVw.image = Image(@"ap_video.png");
        [videoInfoVw addSubview:videoIconImgVw];
        
        durationLbl = [[UILabel alloc] initWithFrame:
                       CGRectMake(30, 0, cellSize-32, bannerHeight)];
        durationLbl.backgroundColor = [UIColor clearColor];
        durationLbl.textAlignment = NSTextAlignmentRight;
        durationLbl.textColor = [UIColor darkGrayColor];
        durationLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:IsPad?12:10];
        [videoInfoVw addSubview:durationLbl];
        durationLbl.tag = 44444;
        
        [cell.contentView addSubview:imgVw];
        [cell.contentView addSubview:nameLbl];
        [cell.contentView addSubview:videoInfoVw];
    }
    
    ALAsset* asset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    if(asset != nil)
    {
        [cell setSelected:[selectedAssets containsAsset:asset]];
        
        imgVw.image = [UIImage imageWithCGImage:[asset aspectRatioThumbnail]];
        nameLbl.text = [[asset defaultRepresentation] filename];
        
        if([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
        {
            videoInfoVw.hidden = NO;
            
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
    headerVw.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6f];
    
    UILabel* albumNameLbl = (UILabel*)[headerVw viewWithTag:12345];
    if(albumNameLbl == nil)
    {
        albumNameLbl = [[UILabel alloc] initWithFrame:
                        CGRectInset(headerVw.bounds, 10, IsPad?5:2)];
        albumNameLbl.backgroundColor = [UIColor clearColor];
        albumNameLbl.textAlignment = NSTextAlignmentLeft;
        albumNameLbl.textColor = [UIColor lightGrayColor];
        albumNameLbl.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:14.0f];
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

/*-(void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath
{
    ALAsset* asset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    [selectedAssets addAsset:asset];
    [self reloadSectionHeadersAndAnyVisibleMatchingItemUsingIndexPath:indexPath];
}

-(BOOL)collectionView:(UICollectionView*)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath*)indexPath
{
    return YES;
}

-(void)collectionView:(UICollectionView*)collectionView didDeselectItemAtIndexPath:(NSIndexPath*)indexPath
{
    ALAsset* asset = availableAssets[indexPath.section][AlbumAssets][indexPath.row];
    [selectedAssets removeAsset:asset];
    [self reloadSectionHeadersAndAnyVisibleMatchingItemUsingIndexPath:indexPath];
}*/

-(void)collectionView:(UICollectionView*)collectionView didEndDisplayingSupplementaryView:(UICollectionReusableView*)view forElementOfKind:(NSString*)elementKind atIndexPath:(NSIndexPath*)indexPath
{
    [sectionHeaders removeObjectForKey:indexPath];
}

@end
