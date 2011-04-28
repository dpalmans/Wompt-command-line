//
//  Wompt.h
//  Wompt
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SocketIOConnection.h"

#include <cdk/cdk.h>


@interface Wompt : NSObject <WebSocketConnectionDelegate> {
@private
    SocketIOConnection * _womptConnection;

    NSString * _channel;
    NSURL * _channelURL;

    NSString * _connectorID;    
    NSString * _connectionID;
    
    NSDateFormatter * _formatter;
    
    NSMutableDictionary * _userlist;
    
    CDKSCREEN *cdkscreen;
    CDKSWINDOW *chatWindow;
    CDKSWINDOW *userListWindow;
}
- (id)initWithChannel:(NSString *)channel;
- (void)run;
- (void)connect;
- (void)sendMessage:(NSString *)message;

@end
