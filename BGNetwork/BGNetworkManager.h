//
//  BGNetworkManager.h
//  BGNetwork
//
//  Created by user on 15/8/14.
//  Copyright (c) 2015年 lcg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BGNetworkConnector.h"
#import "BGNetworkConfiguration.h"
#import "BGNetworkRequest.h"
#import "BGNetworkCache.h"
#import "BGDownloadRequest.h"

/**
 *  网络管理内，是一个单例，需要创建一个网络配置给此类使用
 */
@interface BGNetworkManager : NSObject
+ (instancetype _Nonnull)sharedManager;
/**
 *  网络连接者
 */
@property (nonatomic, strong, readonly) BGNetworkConnector * _Nonnull connector;

/**
 *  网络缓存
 */
@property (nonatomic, strong, readonly) BGNetworkCache * _Nonnull cache;

/**
 *  设置网络配置
 */
@property (nonatomic, strong, readonly) BGNetworkConfiguration * _Nonnull configuration;

/**
 *  设置网络配置
 *
 *  @param configuration 网络配置
 */
- (void)setNetworkConfiguration:(BGNetworkConfiguration * _Nonnull)configuration;


/**
 *  发送请求
 *
 *  @param request                请求
 *  @param successCompletionBlock 成功调回
 *  @param businessFailureBlock   业务失败调回
 *  @param networkFailureBlock    网络失败调回
 */
- (void)sendRequest:(BGNetworkRequest * _Nonnull)request
            success:(BGSuccessCompletionBlock _Nullable)successCompletionBlock
    businessFailure:(BGBusinessFailureBlock _Nullable)businessFailureBlock
     networkFailure:(BGNetworkFailureBlock _Nullable)networkFailureBlock;

/**
 *  发送下载请求
 *
 *  @param request                下载请求
 *  @param downloadProgressBlock  下载的进度条
 *  @param successCompletionBlock 下载成功
 *  @param failureCompletionBlock 下载失败
 */
- (void)sendRequest:(BGDownloadRequest * _Nonnull)request
           progress:(nullable void (^)(NSProgress * _Nonnull downloadProgress)) downloadProgressBlock
            success:(nullable void (^)(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath))successCompletionBlock
            failure:(nullable void (^)(NSError * _Nullable error))failureCompletionBlock;

/**
 *  取消请求
 *
 *  @param url 取消请求的url
 */
- (void)cancelRequestWithUrl:(NSString * _Nonnull)url;

/**
 *  cancel download request
 */
- (void)cancelDownloadRequest:(BGDownloadRequest * _Nonnull)request;
@end
