//
//  SoundCloudPort.m
//  ABMSoundCloudAPI
//
//  Created by AndresBrun on 01/10/14.
//  Copyright (c) 2014 Brun's Software. All rights reserved.
//

#import "SoundCloudPort.h"

#import <AFOAuth2Manager/AFOAuth2Manager.h>
#import <AFNetworking/AFNetworking.h>

#import "NSError+APISoundCloud.h"
#import "NSUserDefaults+soundCloudToken.h"

#import "SoundCloudLoginWebViewController.h"

NSString *SC_API_URL = @"https://api.soundcloud.com";
NSString *PROVIDER_IDENTIFIER = @"SoundCloud_Credentials";

@interface SoundCloudPort ()
@property (strong, nonatomic) AFOAuth2Manager *oAuth2Manager;
@property (strong, nonatomic) AFOAuthCredential *credentials;
@property (strong, nonatomic) NSURLSessionTask *lastOperation;
@property (strong, nonatomic) NSURLSessionTask *lastDownloadOperation;

@property (weak, nonatomic) UIViewController *supportingVC;
@property (strong, nonatomic) NSString *redirectURL;
@end

@implementation SoundCloudPort

- (instancetype)initWithClientId:(NSString *)clientID
                    clientSecret:(NSString *)clientSecret {
    self = [super init];
    if (self) {
        self.oAuth2Manager = [[AFOAuth2Manager alloc] initWithBaseURL:[NSURL URLWithString:SC_API_URL]
                                                             clientID:clientID
                                                               secret:clientSecret];
        self.oAuth2Manager.useHTTPBasicAuthentication = NO;
    }
    return self;
}

- (AFOAuthCredential *)credentials {
    return [AFOAuthCredential retrieveCredentialWithIdentifier:PROVIDER_IDENTIFIER];
}

- (void)loginWithResult:(void (^)(BOOL success))resultBlock
          usingParentVC:(UIViewController *)parentVC
            redirectURL:(NSString *)redirectURL {
    self.redirectURL = redirectURL;
    self.supportingVC = parentVC;
    if([self isValidToken]) {
        resultBlock(YES);
    } else {
        [self handleInvalidTokenWithResult:resultBlock];
    }
}

- (void)handleInvalidTokenWithResult:(void (^)(BOOL success))resultBlock {
    // Check if token doesn't even exist
    NSString *codeStored = [NSUserDefaults getSoundCloudCode];
    if(codeStored) {
        [self getCredentialsForCode:codeStored withResult:^(BOOL success) {
            resultBlock(success);
        }];
    } else {
        __weak typeof(self) weakSelf = self;
        [self presentSoundCloudLoginWebWithResult:^(BOOL result) {
            if (result) {
                [weakSelf handleInvalidTokenWithResult:resultBlock];
            } else {
                resultBlock(result);
            }
        }];
    }
}

- (BOOL)isValidToken {
    return self.credentials && ![self.credentials isExpired];
}

- (void)presentSoundCloudLoginWebWithResult:(void (^)(BOOL result))resultBlock {
    UIViewController *webContainerVC = [SoundCloudLoginWebViewController instantiateWithLoginURL:[self webURLForLogin] redirectURL:self.redirectURL resultBlock:^(BOOL result, NSString *code) {
        if (result) {
            [NSUserDefaults saveSoundCloudToken:code];
        }
        resultBlock(result);
    }];
    
    NSAssert(self.supportingVC!=nil, @"A base navigation has to be defined before try to login.");
    [self.supportingVC presentViewController:webContainerVC animated:YES completion:nil];
}

- (NSString *)webURLForLogin {
    return [NSString stringWithFormat:@"https://soundcloud.com/connect?client_id=%@&response_type=code",self.oAuth2Manager.clientID];
}

- (void)getCredentialsForCode:(NSString *)code
                   withResult:(void (^)(BOOL success))resultBlock {
    if ([self.credentials isExpired]) {
        self.lastOperation = [self.oAuth2Manager authenticateUsingOAuthWithURLString:@"/oauth2/token/" refreshToken:self.credentials.refreshToken success:^(AFOAuthCredential * _Nonnull credential) {
            [AFOAuthCredential storeCredential:credential
                                withIdentifier:PROVIDER_IDENTIFIER];
            resultBlock(YES);
        } failure:^(NSError * _Nonnull error) {
            [NSUserDefaults removeSoundCloudCode];
            [AFOAuthCredential deleteCredentialWithIdentifier:PROVIDER_IDENTIFIER];
            resultBlock(NO);
        }];
    } else {
        self.lastOperation = [self.oAuth2Manager authenticateUsingOAuthWithURLString:@"/oauth2/token/" code:code redirectURI:self.redirectURL success:^(AFOAuthCredential *credential) {
            [AFOAuthCredential storeCredential:credential
                                withIdentifier:PROVIDER_IDENTIFIER];
            resultBlock(YES);
        } failure:^(NSError *error) {
            [NSUserDefaults removeSoundCloudCode];
            [AFOAuthCredential deleteCredentialWithIdentifier:PROVIDER_IDENTIFIER];
            resultBlock(NO);
        }];
    }
}

- (void)requestPlaylistsWithSuccess:(void (^)(NSArray *playlists))successBlock
                            failure:(void (^)(NSError *error))failureBlock {
    NSString *path = @"/me/playlists";
    NSDictionary *params = @{@"oauth_token": self.credentials.accessToken};
    
    self.lastOperation = [self.oAuth2Manager GET:path parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSArray class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)requestPlaylistWithID:(NSString *) playlistID
                  withSuccess:(void (^)(NSDictionary *songsDict))successBlock
                      failure:(void (^)(NSError *error))failureBlock {
    NSString *path = [NSString stringWithFormat:@"/playlists/%@.json", playlistID];
    NSDictionary *params = @{@"oauth_token": self.credentials.accessToken};
    
    self.lastOperation = [self.oAuth2Manager GET:path parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)requestSongsForQuery:(NSString *)query
                       limit:(NSUInteger)limit
                 withSuccess:(void (^)(NSDictionary *songsDict))successBlock
                     failure:(void (^)(NSError *error))failureBlock {
    NSString *path = @"/search/suggest";
    NSDictionary *params = @{@"q":query,
                             @"limit" : @(limit),
                             @"oauth_token": self.credentials.accessToken};
    
    self.lastOperation = [self.oAuth2Manager GET:path parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)requestSongById:(NSString *)songID
            withSuccess:(void (^)(NSDictionary *songDict))successBlock
                failure:(void (^)(NSError *error))failureBlock {

    NSString *path = [NSString stringWithFormat:@"/tracks/%@.json", songID];
    NSDictionary *params = @{@"oauth_token": self.credentials.accessToken};
    
    self.lastOperation = [self.oAuth2Manager GET:path parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)followUserId:(NSString *)userID
         withSuccess:(void (^)(NSDictionary *songDict))successBlock
             failure:(void (^)(NSError *error))failureBlock {
    
    NSString *path = [NSString stringWithFormat:@"/me/followings/%@.json", userID];
    NSDictionary *params = @{@"oauth_token": self.credentials.accessToken};
   
    self.lastOperation = [self.oAuth2Manager GET:path parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)downloadDataForSongURL:(NSString *)songStream
                        inPath:(NSString *)pathToSave
                   withSuccess:(void (^)(NSURL *path))successBlock
                       failure:(void (^)(NSError *error))failureBlock
                      progress:(void (^)(CGFloat progress))progressBlock {

    NSString *urlString = [songStream stringByAppendingString:[NSString stringWithFormat:@"?oauth_token=%@", self.credentials.accessToken]];
    NSURL *url = [NSURL URLWithString: urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    self.lastDownloadOperation = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:pathToSave isDirectory:NO];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error) {
            failureBlock(error);
        } else {
            successBlock(filePath);
        }
    }];
    
    [manager setDownloadTaskDidWriteDataBlock:^(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        progressBlock(totalBytesWritten/(totalBytesExpectedToWrite*1.0));
    }];
    
    [self.lastDownloadOperation resume];
}

- (void)uploadAudioFile:(NSData *)fileData
               mimeType:(NSString*)mimeType
                   meta:(NSDictionary*)params
            withSuccess:(void (^)(NSDictionary *songDict))successBlock
               progress:(void (^)(NSProgress *progress))progressBlock
                failure:(void (^)(NSError *error))failureBlock {
    
    NSString *path = @"/tracks";
    
    NSMutableDictionary *extendedParams = [[NSMutableDictionary alloc] initWithDictionary:params];
    [extendedParams setValue:self.credentials.accessToken forKey:@"oauth_token"];
    
    self.lastOperation = [self.oAuth2Manager POST:path parameters:extendedParams constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        [formData appendPartWithFileData:fileData name:@"track[asset_data]" fileName:@"fileName" mimeType:mimeType];
    } progress: progressBlock success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            successBlock(responseObject);
        } else {
            failureBlock([NSError createParsingError]);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        failureBlock(error);
    }];
}

- (void)cancelLastOperation {
    [self.lastOperation cancel];
    [self.lastDownloadOperation cancel];
}

@end
