//
//  WebSocketConnection.h
//  websocket
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol WebSocketConnectionDelegate <NSObject>
@optional
- (NSDictionary *)additionalHeaders;
- (void)gotData:(NSData *)data;
@end

@interface WebSocketConnection : NSObject {
@protected
    id <WebSocketConnectionDelegate> _delegate;
    NSString *_hostName;
    short _port;

@private
    int _sock;
    dispatch_source_t _readSource;

    uint8_t *_pos;
    uint8_t *_buffer;
    size_t _bufferlen;
    
    uint8_t _readbuf[4096];

    NSData * _challenge;
    
    int _state;
    int _counter;
}

- (id)initWithHost:(NSString *)hostName port:(short)port delegate:(id<WebSocketConnectionDelegate>)delegate;
- (void)sendData:(NSData *)data;
@end
