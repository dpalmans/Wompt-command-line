//
//  SocketIOConnection.h
//  Wompt
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebSocketConnection.h"

@protocol SocketIOConnectionDelegate <WebSocketConnectionDelegate>
@required
- (void)gotConnectionID:(NSString *)connectionID;
- (void)gotJSONMessage:(NSDictionary *)dict;
- (void)gotUnkownMessage:(uint8_t *)message length:(size_t)len;
@end

@interface SocketIOConnection : WebSocketConnection {
@private
    id<SocketIOConnectionDelegate> _socketDelegate;
    bool _gotFirstMessage;
    uint32_t _heartbeat;
    NSString * _connectionID;
}

- (id)initWithHost:(NSString *)hostName port:(short)port delegate:(id<SocketIOConnectionDelegate>)delegate;
- (void)sendMessage:(NSString *)string;
- (void)sendDict:(NSDictionary *)dict;

@end
