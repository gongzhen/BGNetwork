//
//  BGNetworkManager.m
//  BGNetwork
//
//  Created by user on 15/8/14.
//  Copyright (c) 2015年 lcg. All rights reserved.
//

#import "BGNetworkManager.h"
#import "BGNetworkUtil.h"

static BGNetworkManager *_manager = nil;
@interface BGNetworkManager ()<BGNetworkConnectorDelegate>
@property (nonatomic, strong) BGNetworkConnector *connector;
@property (nonatomic, strong) BGNetworkCache *cache;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) dispatch_queue_t dataHandleQueue;
/**
 *  临时储存请求的字典
 */
@property (nonatomic, strong) NSMutableDictionary *tmpRequestDic;
/**
 *  网络配置
 */
@property (nonatomic, strong) BGNetworkConfiguration *configuration;
@property (nonatomic, strong) NSURL *baseURL;
@end

@implementation BGNetworkManager
+ (instancetype)sharedManager{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _manager = [[BGNetworkManager alloc] init];
    });
    return _manager;
}

- (instancetype)init{
    if(self = [super init]){
        //缓存
        _cache = [BGNetworkCache sharedCache];
        
        //工作队列
        _workQueue = dispatch_queue_create("com.BGNetworkManager.workQueue", DISPATCH_QUEUE_SERIAL);
        
        //数据处理队列
        _dataHandleQueue = dispatch_queue_create("com.BGNEtworkManager.dataHandle", DISPATCH_QUEUE_CONCURRENT);
        
        dispatch_async(_workQueue, ^{
            _tmpRequestDic = [[NSMutableDictionary alloc] init];
        });
    }
    return self;
}

- (void)sendRequest:(BGNetworkRequest *)request
            success:(BGSuccessCompletionBlock)successCompletionBlock
    businessFailure:(BGBusinessFailureBlock)businessFailureBlock
     networkFailure:(BGNetworkFailureBlock)networkFailureBlock {
    NSParameterAssert(self.connector);
    dispatch_async(self.workQueue, ^{
        switch (request.cachePolicy) {
            case BGNetworkRquestCacheNone:
                //请求网络数据
                [self loadNetworkDataWithRequest:request success:successCompletionBlock businessFailure:businessFailureBlock networkFailure:networkFailureBlock];
                break;
            case BGNetworkRequestCacheDataAndReadCacheOnly:
            case BGNetworkRequestCacheDataAndReadCacheLoadData:
                //读取缓存并且请求数据
                [self readCacheAndRequestData:request completion:^(BGNetworkRequest *request, id responseObject) {
                    if(responseObject){
                        /*
                         缓存策略
                         BGNetworkRequestCacheDataAndReadCacheOnly：获取缓存数据直接调回，不再请求
                         BGNetworkRequestCacheDataAndReadCacheLoadData：缓存数据成功调回并且重新请求网络
                         */
                        [self success:request responseObject:responseObject completion:successCompletionBlock];
                        
                        if(request.cachePolicy == BGNetworkRequestCacheDataAndReadCacheLoadData){
                            [self loadNetworkDataWithRequest:request success:successCompletionBlock businessFailure:businessFailureBlock networkFailure:networkFailureBlock];
                        }
                    }
                    else{
                        //无缓存数据，则还需要再请求网络
                        [self loadNetworkDataWithRequest:request success:successCompletionBlock businessFailure:businessFailureBlock networkFailure:networkFailureBlock];
                    }
                }];
        }
    });
}

- (void)loadNetworkDataWithRequest:(BGNetworkRequest *)request
                           success:(BGSuccessCompletionBlock)successCompletionBlock
                   businessFailure:(BGBusinessFailureBlock)businessFailureBlock
                    networkFailure:(BGNetworkFailureBlock)networkFailureBlock{
    //临时保存请求
    NSString *requestKey = [[NSURL URLWithString:request.methodName relativeToURL:self.baseURL] absoluteString];
    self.tmpRequestDic[requestKey] = request;
    
    //发送请求
    __weak BGNetworkManager *weakManager = self;
    switch (request.httpMethod) {
        case BGNetworkRequestHTTPGet:{
            [self.connector sendGETRequest:request.methodName parameters:request.parametersDic success:^(NSURLSessionDataTask *task, NSData *responseData) {
                [weakManager networkSuccess:request task:task responseData:responseData success:successCompletionBlock businessFailure:businessFailureBlock];
            } failed:^(NSURLSessionDataTask *task, NSError *error) {
                [weakManager networkFailure:request error:error completion:networkFailureBlock];
            }];
        }
            break;
        case BGNetworkRequestHTTPPost:{
            [self.connector sendPOSTRequest:request.methodName parameters:request.parametersDic success:^(NSURLSessionDataTask *task, NSData *responseData) {
                [weakManager networkSuccess:request task:task responseData:responseData success:successCompletionBlock businessFailure:businessFailureBlock];
            } failed:^(NSURLSessionDataTask *task, NSError *error) {
                [weakManager networkFailure:request error:error completion:networkFailureBlock];
            }];
        }
            break;
        default:
            break;
    }
}

#pragma mark - cache method
- (void)readCacheAndRequestData:(BGNetworkRequest *)request completion:(void (^)(BGNetworkRequest *request, id responseObject))completionBlock{
    __weak BGNetworkManager *weakManager = self;
    NSString *cacheKey = [BGNetworkUtil keyFromParamDic:request.parametersDic methodName:request.methodName baseURL:self.configuration.baseURLString];
    [self.cache queryCacheForKey:cacheKey completed:^(NSData *data) {
        dispatch_async(weakManager.dataHandleQueue, ^{
            //解析数据
            id responseObject = [weakManager parseResponseData:data];
            dispatch_async(weakManager.workQueue, ^{
                if(completionBlock) {
                    completionBlock(request, responseObject);
                }
            });
        });
    }];
}

- (void)cacheResponseData:(NSData *)responseData request:(BGNetworkRequest *)request{
    NSString *cacheKey = [BGNetworkUtil keyFromParamDic:request.parametersDic methodName:request.methodName baseURL:self.configuration.baseURLString];
    //缓存数据
    [self.cache storeData:responseData forKey:cacheKey];
}

#pragma mark - set method
- (void)setNetworkConfiguration:(BGNetworkConfiguration *)configuration{
    NSParameterAssert(configuration);
    NSParameterAssert(configuration.baseURLString);
    self.connector = [[BGNetworkConnector alloc] initWithBaseURL:configuration.baseURLString delegate:self];
    self.baseURL = [NSURL URLWithString:configuration.baseURLString];
    _configuration = configuration;
}

#pragma mark - 网络请求回来调用的方法
- (void)networkSuccess:(BGNetworkRequest *)request
                  task:(NSURLSessionDataTask *)task
          responseData:(NSData *)responseData
               success:(BGSuccessCompletionBlock)successCompletionBlock
       businessFailure:(BGBusinessFailureBlock)businessFailureBlock{
    
    dispatch_async(self.dataHandleQueue, ^{
        //对数据进行解密
        NSData *decryptData = [self.configuration decryptResponseData:responseData response:task.response request:request];
        //解析数据
        id responseObject = [self parseResponseData:decryptData];
        dispatch_async(self.workQueue, ^{
            if(responseObject && [self.configuration shouldBusinessSuccessWithResponseData:responseObject task:task request:request]) {
                if([self.configuration shouldCacheResponseData:responseObject task:task request:request]) {
                    //缓存解密之后的数据
                    [self cacheResponseData:decryptData request:request];
                }
                //成功回调
                [self success:request responseObject:responseObject completion:successCompletionBlock];
            }
            else {
                [self businessFailure:request response:responseObject completion:businessFailureBlock];
            }
        });
    });
    
}

- (void)success:(BGNetworkRequest *)request
 responseObject:(id)responseObject
     completion:(BGSuccessCompletionBlock)successCompletionBlock{
    dispatch_async(self.dataHandleQueue, ^{
        id resultObject = nil;
        @try {
            //调用request方法中的数据处理，将数据处理成想要的model
            resultObject = [request processResponseObject:responseObject];
        }
        @catch (NSException *exception) {
            //崩溃则删除对应的缓存数据
            NSString *cacheKey = [BGNetworkUtil keyFromParamDic:request.parametersDic methodName:request.methodName baseURL:self.configuration.baseURLString];
            [self.cache removeCacheForKey:cacheKey];
        }
        @finally {
        }
        //成功回调
        dispatch_async(dispatch_get_main_queue(), ^{
            if(successCompletionBlock) {
                successCompletionBlock(request, resultObject);
            }
        });
    });
}

/**
 *  网络成功，业务失败
 */
- (void)businessFailure:(BGNetworkRequest *)request response:(id)response completion:(BGNetworkFailureBlock)businessFailureBlock{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(businessFailureBlock) {
            businessFailureBlock(request, response);
        }
    });
}

/**
 *  网络失败
 */
- (void)networkFailure:(BGNetworkRequest *)request error:(NSError *)error completion:(BGNetworkFailureBlock)networkFailureBlock{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(networkFailureBlock) {
            networkFailureBlock(request, error);
        }
    });
}

#pragma mark - cancel request
- (void)cancelRequestWithUrl:(NSString *)url{
    [self.connector cancelRequest:url];
}

#pragma mark - Util method
/**
 *  解析json数据
 */
- (id)parseResponseData:(NSData *)responseData{
    if(responseData == nil){
        return nil;
    }
    return [BGNetworkUtil parseJsonData:responseData];
}

#pragma mark - BGNetworkConnectorDelegate
- (NSDictionary *)allHTTPHeaderFieldsWithNetworkConnector:(BGNetworkConnector *)connector request:(NSURLRequest *)request{
    //取出请求
    BGNetworkRequest *networkRequest = self.tmpRequestDic[request.URL.absoluteString];
    return [self.configuration requestHTTPHeaderFields:networkRequest];
}

- (NSString *)queryStringForURLWithNetworkConnector:(BGNetworkConnector *)connector parameters:(NSDictionary *)paramters request:(NSURLRequest *)request{
    //取出请求
    BGNetworkRequest *networkRequest = self.tmpRequestDic[request.URL.absoluteString];
    return [self.configuration queryStringForURLWithRequest:networkRequest];
}

- (NSData *)dataOfHTTPBodyWithNetworkConnector:(BGNetworkConnector *)connector parameters:(NSDictionary *)paramters request:(NSURLRequest *)request error:(NSError *__autoreleasing *)error{
    BGNetworkRequest *networkRequest = self.tmpRequestDic[request.URL.absoluteString];
    return [self.configuration httpBodyDataWithRequest:networkRequest];
}
@end
