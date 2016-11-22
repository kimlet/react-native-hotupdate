//
//  ReactNativeHotFix.m
//  ReactNativeHotFix
//
//  Created by JinBangzhu on 11/11/2016.
//  Copyright © 2016 kimber. All rights reserved.
//

#import "ReactNativeHotFix.h"

@implementation ReactNativeHotFix


static ReactNativeHotFix *RNAUTOUPDATER_SINGLETON = nil;
static bool isFirstAccess = YES;


+(id)sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isFirstAccess = NO;
        RNAUTOUPDATER_SINGLETON = [[super allocWithZone:NULL] init];
    });
    
    return RNAUTOUPDATER_SINGLETON;
}

-(void) init:(NSString *)defaultRootPatch extraRootPath:(NSString *) extraRootPath upgradeUrl:(NSURL *) upgradeUrl patchUrl:(NSURL *) patchUrl
{
    self.defaultaJSPath = [defaultRootPatch stringByAppendingPathComponent:@"index.ios.jsbundle"];
    self.extraJSPath = [extraRootPath stringByAppendingPathComponent:@"index.ios.jsbundle"];
    
    self.defaultaAssetsPath = [defaultRootPatch stringByAppendingPathComponent:@"assets"];
    self.extraAssetsPath = [extraRootPath stringByAppendingPathComponent:@"assets"];;
    
    self.defaultZipBundlePath = [defaultRootPatch stringByAppendingPathComponent:@"ios.zip"];
    self.extraZipBundlePath = [extraRootPath stringByAppendingPathComponent:@"ios.zip"];
    
    self.upgradeUrl = upgradeUrl;
    self.patchUrl = patchUrl;
    
    self.defaultRootPath = defaultRootPatch;
    self.extraRootPath = extraRootPath;
    
    [self initialResource];
}


-(void) initialResource
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.extraZipBundlePath]) {
        [[NSFileManager defaultManager] copyItemAtPath:self.defaultZipBundlePath toPath:self.extraZipBundlePath error:nil];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.extraJSPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:self.extraJSPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:self.extraAssetsPath error:nil];
            
            // unzip file
            [SSZipArchive unzipFileAtPath:self.extraZipBundlePath toDestination: self.extraRootPath];
        }
    }else{
        NSString *defaultInfoJsonFile = [self.defaultRootPath stringByAppendingPathComponent:@"info.json"];
        NSString *extraInfoJsonFile = [self.extraRootPath stringByAppendingPathComponent:@"info.json"];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.extraJSPath]) {
            // unzip file
            [SSZipArchive unzipFileAtPath:self.extraZipBundlePath toDestination: self.extraRootPath];
        }
        int defaultVersionCode = [self getVersionCode:defaultInfoJsonFile];
        int extraVersionCode = [self getVersionCode:extraInfoJsonFile];
        
        if (defaultVersionCode > extraVersionCode) {
            [[NSFileManager defaultManager] removeItemAtPath:self.extraJSPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:self.extraAssetsPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:self.extraZipBundlePath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:extraInfoJsonFile error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[self.extraJSPath stringByAppendingString:@".meta"] error:nil];
            
            
            [[NSFileManager defaultManager] copyItemAtPath:self.defaultZipBundlePath toPath:self.extraZipBundlePath error:nil];
            [SSZipArchive unzipFileAtPath:self.extraZipBundlePath toDestination: self.extraRootPath];
        }
    }
}

-(int)getVersionCode:(NSString *) infoJsonPath
{
    NSData *infoJsonData = [NSData dataWithContentsOfFile:infoJsonPath];
    
    id infoJson =  [NSJSONSerialization JSONObjectWithData:infoJsonData options:0 error:nil];
    NSString *defaultJsonVersion = [infoJson objectForKey:@"version"];
    
    defaultJsonVersion = [defaultJsonVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
    int defaultVersion = [defaultJsonVersion intValue];
    NSLog(@"%@", [infoJson objectForKey:@"version"]);
    
    return defaultVersion;
}

-(void)start
{
    [self loadUpgradeInfo:self.upgradeUrl completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            if (httpResp.statusCode == 200) {
                /**
                 *{
                 "patchFileMd5": "ccefa78e34de5c11c76f12d994c34088",
                 "originFileMd5": "9b9119e299bc6c1b2928f5ea37b93ddc",
                 "targetFileMd5": "9b9119e299bc6c1b2928f5ea37b93ddc"
                 *}
                 */
                NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                NSString *originFileMd5 = json[@"originFileMd5"];
                NSString *targetFileMd5 = json[@"targetFileMd5"];
                NSString *patchFileMd5 = json[@"patchFileMd5"];
                
                NSString *oldZipBundleFile;
                
                if (self.defaultaJSPath && [[NSFileManager defaultManager] fileExistsAtPath:self.defaultZipBundlePath]) {
                    oldZipBundleFile = self.defaultZipBundlePath;
                }
                if (self.extraJSPath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraZipBundlePath]) {
                    oldZipBundleFile = self.extraZipBundlePath;
                }
                
                if ([[NSFileManager defaultManager] fileExistsAtPath:oldZipBundleFile]) {
                    
//                    [self copyAssetsFolderIfNeed];
                    
                    NSString *oldZipBundleFileMD5 = [self getZipBundleFileMd5];
                    if ([oldZipBundleFileMD5 isEqualToString:originFileMd5]) {
                        // start to download
                        NSString *patchFile = [self.extraZipBundlePath stringByAppendingString:@"_patch_"];
                        
                        [self downloadPatchFileAndMerge:self.patchUrl originFile:oldZipBundleFile targetFile:self.extraZipBundlePath targetFileMD5:targetFileMd5 patchFile: patchFile patchFileMD5:patchFileMd5];
                        
                    }else{
                        [self.delegate ReactNativeHotFix:self updateFailed:@"origin file verify md5 failed"];
                    }
                    
                }else{
                    /**
                     * does not find rnbundle/index.ios.bundle
                     */
                    [self.delegate ReactNativeHotFix:self updateFailed:@"file not found error"];
                }
                
                NSLog(@"success %@", json[@"originFileMd5"]);
            }else{
                [self.delegate ReactNativeHotFix:self updateFailed:@"service error"];
            }
        }else{
            [self.delegate ReactNativeHotFix:self updateFailed:@"network error"];
        }
    }];
}

-(void) downloadPatchFileAndMerge:(NSURL *) patchUrl originFile:(NSString *) originFile targetFile:(NSString *) targetFile targetFileMD5:(NSString *) targetFileMD5 patchFile:(NSString *) patchFile patchFileMD5:(NSString *) patchFileMD5{
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        //Background Thread
        NSData* fileData = [NSData dataWithContentsOfURL: patchUrl];
        NSString *downloadPatchFileMD5 = [fileData MD5];
        if ([downloadPatchFileMD5 isEqualToString:patchFileMD5]) {
            [fileData writeToFile:patchFile atomically:YES];
            // create temp target file
            NSString *targetFileTemp = [targetFile stringByAppendingString:@"temp"];
            
            // merge file
            [self bspatch:originFile newFile:targetFileTemp patchFile:patchFile];
            
            // get merged targetFile md5
            NSData *targetFileNsData = [NSData dataWithContentsOfFile:targetFileTemp];
            NSString *mergedTargetFileMD5 = [targetFileNsData MD5];
            
            
            if ([mergedTargetFileMD5 isEqualToString:targetFileMD5]) {// merge success
                
                // remove old zipBundle file
                [[NSFileManager defaultManager] removeItemAtPath:targetFile error:nil];
                
                // use target zipBundle file
                [[NSFileManager defaultManager] moveItemAtPath:targetFileTemp toPath:targetFile error:nil];
                
                // remove patch file
                [[NSFileManager defaultManager] removeItemAtPath:patchFile error:nil];
                
                // remove old jsbundle file and assets
                [[NSFileManager defaultManager] removeItemAtPath:self.extraJSPath error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:[self.extraJSPath stringByAppendingString:@".meta"] error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:self.extraAssetsPath error:nil];
            
                // unzip zipBundle file
                [SSZipArchive unzipFileAtPath:targetFile toDestination: self.extraRootPath];
                
                [self.delegate ReactNativeHotFix:self updateSuccess:@"success"];
            }else{// merge failed
                NSLog(@"bspatch failed");
                [self.delegate ReactNativeHotFix:self updateFailed: @"target file verify md5 failed"];
            }
            
            
        }else{
            [self.delegate ReactNativeHotFix:self updateFailed:@"patch file verify md5 failed"];
        }
    });
    
}

// load upgrade json info
-(void) loadUpgradeInfo:(NSURL *) requestUrl  completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler{
    
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:requestUrl];
    request.HTTPMethod = @"GET";
    
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request addValue:@"no-cache, no-store, must-revalidate" forHTTPHeaderField:@"Cache-Control"];
    
    NSError *error = nil;
    
    NSDictionary *dictionary = @{@"md5": [self getJSBundleFileMd5]};
    NSData *postData = [NSJSONSerialization dataWithJSONObject:dictionary options:kNilOptions error:&error];
    [request setHTTPBody:postData];
    
    
    if(!error){
        NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:completionHandler];
        
        [dataTask resume];
    }

}

-(void) copyAssetsFolderIfNeed{
    NSString *defaultAssetsFile = self.defaultaAssetsPath;
    NSString *extraAssetsFile = self.extraAssetsPath;
    
    
    BOOL isDir;
    // must be true
    if (defaultAssetsFile && [[NSFileManager defaultManager] fileExistsAtPath:defaultAssetsFile isDirectory:&isDir]) {
        // not found on sdcard
        if (extraAssetsFile &&![[NSFileManager defaultManager] fileExistsAtPath:extraAssetsFile isDirectory:&isDir]) {
            bool copyFolderResult = [[NSFileManager defaultManager] copyItemAtPath:defaultAssetsFile toPath:extraAssetsFile error:nil];
            NSLog(@"copyFolderResult:%@", copyFolderResult? @"success" : @"failed");
        }else{
            NSLog(@"target folder already exists");
        }
    }
}

-(NSString *) getJSBundleFileMd5{
    if (self.extraJSPath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraJSPath]) {
        // use sdcard jsbundle file
        NSData *originFileNsData = [NSData dataWithContentsOfFile:self.extraJSPath];
        NSString *originFileMD5 = [originFileNsData MD5];
        return originFileMD5;
    }else{
        // use default jsbundle file
        NSData *defaultFileNsData = [NSData dataWithContentsOfFile:self.defaultaJSPath];
        NSString *defaultFileMD5 = [defaultFileNsData MD5];
        
        return defaultFileMD5;
    }

}

-(NSString *) getZipBundleFileMd5{
    if (self.extraZipBundlePath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraZipBundlePath]) {
        // use sdcard jsbundle file
        NSData *originFileNsData = [NSData dataWithContentsOfFile:self.extraZipBundlePath];
        NSString *originFileMD5 = [originFileNsData MD5];
        return originFileMD5;
    }else{
        // use default jsbundle file
        NSData *defaultFileNsData = [NSData dataWithContentsOfFile:self.defaultZipBundlePath];
        NSString *defaultFileMD5 = [defaultFileNsData MD5];
        
        return defaultFileMD5;
    }
    
}


-(void) bspatch:(NSString *)oldFile newFile:(NSString *)newFile patchFile:(NSString *)patchFile
{
    bspatch([oldFile UTF8String], [newFile UTF8String], [patchFile UTF8String]);
}

-(NSURL *) getUrl
{
    if (self.extraJSPath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraJSPath]) {
        return [NSURL URLWithString: self.extraJSPath];
    }else{
        return [NSURL URLWithString: [@"file://" stringByAppendingString:self.defaultaJSPath] ];
    }
}


@end

