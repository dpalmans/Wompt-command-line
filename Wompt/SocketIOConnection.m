//
//  SocketIOConnection.m
//  Wompt
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SocketIOConnection.h"
#import "NSDictionary+BSJSONAdditions.h"


@implementation SocketIOConnection

- (id)initWithHost:(NSString *)hostName port:(short)port delegate:(id<SocketIOConnectionDelegate>)delegate
{
    self = [super initWithHost:hostName port:port delegate:delegate];
    if (self != nil) {
        _heartbeat = 1;
        _socketDelegate = delegate;
    }
    
    return self;
}
- (void) dealloc
{
    [_connectionID release];
    [super dealloc];
}

// Overridden from base class
- (void)handleData:(NSData *)data
{
    uint8_t * pos;
    uint8_t * buffer = (uint8_t *)[data bytes];
    size_t len = (size_t)[data length];
    
    // Validate the message has a header that looks like '~m~len~m~'
    if (len < 7 || (buffer[0] != '~' && buffer[1] != 'm' && buffer[2] != '~')) {
        [_socketDelegate gotUnkownMessage:buffer length:len];
        return;
    }
    
    // Ignore the header
    pos = buffer + 7;
    while(*(pos-2) != 'm' || *(pos-1) != '~'){
        pos++;
        
        // Have we blown past our len?
        if ((pos - buffer) > len) {
            [_socketDelegate gotUnkownMessage:buffer length:len];
            break;                    
        }
    }
    
    len -= (pos - buffer);
    
    if (_connectionID == nil) {
        // First message is always the connetion id
        _connectionID = [[NSString alloc] initWithBytes:pos length:len encoding:NSUTF8StringEncoding];
        [_socketDelegate gotConnectionID:_connectionID];
    } else if(pos[0] == '~' && pos[2] == '~') {
        switch(pos[1]) {
            case 'j': {
                NSString * jsonString = [[[NSString alloc] initWithBytes:pos length:len encoding:NSUTF8StringEncoding] autorelease];
                NSDictionary * dict = [NSDictionary dictionaryWithJSONString:jsonString];
                [_socketDelegate gotJSONMessage:dict];
                break;
            }
                
            case 'h':
                [self sendMessage:[NSString stringWithFormat:@"~h~%d", _heartbeat++]];
                break;
        }
    } else {
        [_socketDelegate gotUnkownMessage:pos length:len];
    }
    
}

- (void)sendMessage:(NSString *)string
{
    NSString * message = [NSString stringWithFormat:@"~m~%u~m~%@", [string length], string];
    [self sendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendDict:(NSDictionary *)dict
{
    [self sendMessage:[dict jsonStringValue]];
}

@end
