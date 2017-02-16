//
//  GameClientHotFix.m
//  ReactNativeHotFix
//
//  Created by JinBangzhu on 06/02/2017.
//  Copyright © 2017 kimber. All rights reserved.
//

#import "GameClientHotFix.h"

@implementation GameClientHotFix


static GameClientHotFix * GAMECLIENTHOTFIX_SINGLETON = nil;
static bool isFirstAccess = YES;

+(id) sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isFirstAccess = NO;
        GAMECLIENTHOTFIX_SINGLETON = [[super allocWithZone:NULL] init];
    });
    
    return GAMECLIENTHOTFIX_SINGLETON;
}

-(void) init:(NSString *)defaultRootPath extraRootPath:(NSString *)extraRootPath upgradeUrl:(NSURL *)upgradeUrl{
    self.defaultRootPath = defaultRootPath;
    self.extraRootPath = extraRootPath;
    self.upgradeUrl = upgradeUrl;
    
    self.defaultGameClientZipFilePath = [defaultRootPath stringByAppendingPathComponent:@"game_client.zip"];
    self.extraGameClientZipFilePath = [self.extraRootPath stringByAppendingPathComponent:@"game_client.zip"];
    self.extraGameClientPath = [extraRootPath stringByAppendingPathComponent:@"game_client"];
    
    
    [self initResource];
}

-(void) initResource{
    if(![[NSFileManager defaultManager] fileExistsAtPath:self.extraGameClientPath]){
        [[NSFileManager defaultManager] copyItemAtPath:self.defaultGameClientZipFilePath toPath:self.extraGameClientZipFilePath error:nil];
        [SSZipArchive unzipFileAtPath:self.extraGameClientZipFilePath toDestination:self.extraGameClientPath];
    }else{
        NSString *defaultInfoJsonFile = [self.defaultRootPath stringByAppendingPathComponent:@"info.json"];
        NSString *extraInfoJsonFile = [self.extraGameClientPath stringByAppendingPathComponent:@"info.json"];
        
        int defaultVersionCode = [self getVersionCode:defaultInfoJsonFile];
        int extraVersionCode = [self getVersionCode:extraInfoJsonFile];
        
        if (defaultVersionCode > extraVersionCode) {
            [[NSFileManager defaultManager] removeItemAtPath:self.extraRootPath error:nil];
            
            [[NSFileManager defaultManager] copyItemAtPath:self.defaultGameClientZipFilePath toPath:self.extraGameClientZipFilePath error:nil];
            [SSZipArchive unzipFileAtPath:self.extraGameClientZipFilePath toDestination:self.extraRootPath];
        }
    }
}

-(void) start{
    [self loadUpgradeInfo:self.upgradeUrl completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            if (httpResp.statusCode == 200) {
                NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                
                NSString *msg = json[@"msg"];
                NSNumber *ok = json[@"ok"];
                
                if (ok.boolValue) {
                    NSDictionary *md5 = json[@"md5"];
                    
                    NSString *originFileMd5 = [md5 objectForKey:@"originFileMd5"];
                    NSString *targetFileMd5 = [md5 objectForKey:@"targetFileMd5"];
                    NSString *patchFileMd5 = [md5 objectForKey:@"patchFileMd5"];
                    
                    self.patchUrl = [NSURL URLWithString:json[@"patch_url"]];
                    [self start:originFileMd5 targetFileMd5:targetFileMd5 patchFileMd5:patchFileMd5];
                    
                    
                    NSLog(@"success %@", json[@"originFileMd5"]);
                }else{
                    [self.delegate GameClientHotFix:self updateFailed:[@"response json error :" stringByAppendingString:msg]];
                }
            }else{
                [self.delegate GameClientHotFix:self updateFailed:@"service error"];
            }
        }else{
            [self.delegate GameClientHotFix:self updateFailed:@"network error"];
        }
    }];
}


-(void)start: (NSString *) originFileMd5 targetFileMd5:(NSString *) targetFileMd5 patchFileMd5:(NSString *) patchFileMd5
{
    NSString *oldZipBundleFile;
    
    if (self.defaultGameClientZipFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.defaultGameClientZipFilePath]) {
        oldZipBundleFile = self.defaultGameClientZipFilePath;
    }
    if (self.extraGameClientZipFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraGameClientZipFilePath]) {
        oldZipBundleFile = self.extraGameClientZipFilePath;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:oldZipBundleFile]) {
        
        //                    [self copyAssetsFolderIfNeed];
        
        NSString *oldZipBundleFileMD5 = [self getZipBundleFileMd5];
        if ([oldZipBundleFileMD5 isEqualToString:originFileMd5]) {
            // start to download
            NSString *patchFile = [self.extraGameClientZipFilePath stringByAppendingString:@"_patch_"];
            
            [self downloadPatchFileAndMerge:self.patchUrl originFile:oldZipBundleFile targetFile:self.extraGameClientZipFilePath targetFileMD5:targetFileMd5 patchFile: patchFile patchFileMD5:patchFileMd5];
            
        }else{
            [self.delegate GameClientHotFix:self updateFailed:@"origin file verify md5 failed"];
        }
        
    }else{
        /**
         * does not find rnbundle/index.ios.bundle
         */
        [self.delegate GameClientHotFix:self updateFailed:@"file not found error"];
    }
    
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
                
                // remove old zip file
                [[NSFileManager defaultManager] removeItemAtPath:targetFile error:nil];
                
                // use target zip file
                [[NSFileManager defaultManager] moveItemAtPath:targetFileTemp toPath:targetFile error:nil];
                
                // remove patch file
                [[NSFileManager defaultManager] removeItemAtPath:patchFile error:nil];
                
                [[NSFileManager defaultManager] removeItemAtPath:self.extraGameClientPath error:nil];
                
                
                // unzip zipBundle file
                [SSZipArchive unzipFileAtPath:targetFile toDestination: self.extraGameClientPath];
                
                [self.delegate GameClientHotFix:self updateSuccess:@"success"];
            }else{// merge failed
                NSLog(@"bspatch failed");
                [self.delegate GameClientHotFix:self updateFailed: @"target file verify md5 failed"];
            }
            
            
        }else{
            [self.delegate GameClientHotFix:self updateFailed:@"patch file verify md5 failed"];
        }
    });
    
}


-(NSString *) getZipBundleFileMd5{
    if (self.extraGameClientZipFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.extraGameClientZipFilePath]) {
        // use sdcard jsbundle file
        NSData *originFileNsData = [NSData dataWithContentsOfFile:self.extraGameClientZipFilePath];
        NSString *originFileMD5 = [originFileNsData MD5];
        return originFileMD5;
    }else{
        // use default jsbundle file
        NSData *defaultFileNsData = [NSData dataWithContentsOfFile:self.defaultGameClientZipFilePath];
        NSString *defaultFileMD5 = [defaultFileNsData MD5];
        
        return defaultFileMD5;
    }
    
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
    
    if(!error){
        NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:completionHandler];
        
        [dataTask resume];
    }
    
}

-(void) bspatch:(NSString *)oldFile newFile:(NSString *)newFile patchFile:(NSString *)patchFile
{
    bspatch([oldFile UTF8String], [newFile UTF8String], [patchFile UTF8String]);
}




-(int)getVersionCode:(NSString *) infoJsonPath
{
    NSData *infoJsonData = [NSData dataWithContentsOfFile:infoJsonPath];
    
    id infoJson =  [NSJSONSerialization JSONObjectWithData:infoJsonData options:0 error:nil];
    NSString *defaultJsonVersion = [infoJson objectForKey:@"version"];
    
    int defaultVersion = [defaultJsonVersion intValue];
    NSLog(@"%@", [infoJson objectForKey:@"version"]);
    
    return defaultVersion;
}


-(NSString *) getExtraVersion{
    return [NSString stringWithFormat:@"%d", [self getVersionCode:[self.extraGameClientPath stringByAppendingPathComponent:@"info.json"]]];
}
-(NSString *) getDefaultVersion{
    return [NSString stringWithFormat:@"%d", [self getVersionCode:[self.defaultRootPath stringByAppendingPathComponent:@"info.json"]]];
}

@end
