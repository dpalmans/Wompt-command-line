//
//  WebSocketConnection.m
//  websocket
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 Apple. All rights reserved.
//

#import "WebSocketConnection.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <dispatch/dispatch.h>
#include <CommonCrypto/CommonDigest.h>


@interface WebSocketConnection(PrivateStuff)
- (void)read;
- (void)sendHeaders;
@end


@implementation WebSocketConnection

- (id)initWithHost:(NSString *)hostName port:(short)port delegate:(id<WebSocketConnectionDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = [delegate retain];
        _hostName = [hostName retain];
        _port = port;
        
        _bufferlen = 4096;
        _buffer = malloc(_bufferlen);
        _state = 0;
        _counter = 0;

        // Try to connect to host
        char portString[6] = {0};
        struct addrinfo hints = {0};
        hints.ai_family         = PF_INET;
        hints.ai_socktype       = SOCK_STREAM;
        hints.ai_protocol       = IPPROTO_TCP;
        sprintf(portString, "%hu", port);

        struct addrinfo * ai = NULL;
        struct addrinfo * next = NULL;

        int ret = getaddrinfo([_hostName UTF8String], portString, &hints, &ai);
        if (ret != 0) {
            NSLog(@"getaddrinfo() failed (%d): %s", ret, gai_strerror(ret));
            [self release];
            return nil;
        }

        _sock = -1;
        for (next = ai; next != NULL && _sock == -1; next = next->ai_next) {
            _sock = socket(next->ai_family, next->ai_socktype, next->ai_protocol);
            if (_sock != -1) {
                ret = connect(_sock, ai->ai_addr, ai->ai_addrlen);
                if (ret != 0) {
                    close(_sock);
                    _sock = -1;
                }
            }
        }

        freeaddrinfo(ai);
        
        // Were we able to connect?
        if (_sock == -1) {
            NSLog(@"Unable to connect.");
            [self release];
            return nil;
        }
        
        int opt = 1;
        setsockopt(_sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));    
        setsockopt(_sock, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));

        dispatch_queue_t readQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sock, 0, readQueue);

        dispatch_source_set_event_handler(_readSource, ^{
            [self read];
        });
        dispatch_source_set_cancel_handler(_readSource, ^{
            dispatch_release(_readSource);    
            close(_sock);
        });

        dispatch_resume(_readSource);
        
        // Try sending the http headers
        [self sendHeaders];
    }
    
    return self;
}

- (void)dealloc
{
    if (_buffer) free(_buffer);
    [_hostName release];
    [_delegate release];
    [_challenge release];
    [super dealloc];
}

- (void)handleData:(NSData *)data
{
    if ([_delegate respondsToSelector:@selector(gotData:)])
        [_delegate gotData:data];
}

- (void)parse:(uint8_t)byte
{
    switch(_state) {
        case 0: //TODO: Actually parse html header instead of looking for 6 newlines...
            if (byte == '\n')
                _counter++;
            if (_counter == 6) {
                _state = 1;
                _counter = 0;
            }
            break;
            
        case 1: {
            uint8_t *challenge = (uint8_t *)[_challenge bytes];
            if (byte != challenge[_counter]) {
                NSLog(@"Challenge failed!");
                _counter = 16; //Ignore for now.
            } else {            
                _counter++;
            }
            
            if (_counter == 16) {
                [_challenge release];
                _counter = 0;
                _state = 2;
            }
            break;
        }
            
        case 2:
            if (byte == 0x00) {
                _state = 3;
                _pos = _buffer;
            } else {
                NSLog(@"Unexpected char: %c", byte);
            }
            break;
            
        case 3:
            if (byte == 0xff) {
                _state = 2;
                NSData * data = [NSData dataWithBytesNoCopy:_buffer length:(_pos - _buffer) freeWhenDone:NO];
                [self handleData:data];
            } else {
                *_pos++ = byte;
                if ((_pos - _buffer) == _bufferlen) {
                    _buffer = realloc(_buffer, _bufferlen * 2);
                    _pos = _buffer + _bufferlen;                            
                    _bufferlen *= 2;
                }
            }
            break;
    }
}

- (void)read
{    
    uint8_t * pos = _readbuf;
    ssize_t len = read(_sock, _readbuf, sizeof(_readbuf));
    if (len == 0) {
        [NSException raise:@"Socket closed while reading" format:@"Socket closed while reading"];
    } else if (len == -1) {
        [NSException raise:@"Read failed..." format:@"Read failed (%d): %s", errno, strerror(errno)];
    }
    
    while (len) {
        [self parse:*pos];
        len--;
        pos++;
    }
}

- (void)send:(const void *)data length:(size_t)len
{
    ssize_t size;
    const uint8_t * pos = data;
    
    while (len > 0) {
        size = write(_sock, pos, len);
        if (size == -1) {
            [NSException raise:@"Failed to send data" format:@"Failed to send data (%d): %s", errno, strerror(errno)];
        }
        
        len -= size;
        pos += size;
    }
}

- (void)sendData:(NSData *)data
{
    uint8_t header = 0x00;
    uint8_t trailer = 0xff;
    
    [self send:&header length:sizeof(header)];    
    [self send:[data bytes] length:[data length]];
    [self send:&trailer length:sizeof(trailer)];    
}


- (NSString *)generateKeyString:(uint32_t *)keyVal
{
    int numSpaces = (arc4random() % 12) + 1;
    int numChars = (arc4random() % 12) + 1; 
    
    uint32_t num = (arc4random() % (INT32_MAX / numSpaces)) * numSpaces;    
    NSMutableString * s = [NSMutableString stringWithFormat:@"%u", num];
    *keyVal = num / numSpaces;
     
    for (int i = 0; i < numChars; i++) {
        unsigned long pos = (arc4random() % [s length]) + 1;

        char c = arc4random() % (14+68);
        c = (c <= 14) ? (c + 0x21) : (c - 14 + 0x3a);
        
        NSString * s2 = [NSString stringWithFormat:@"%c", c];
        
        [s insertString:s2 atIndex:pos];
    }

    for (int i = 0; i < numSpaces; i++) {
        unsigned long pos = (arc4random() % ([s length]-1)) + 1;
        [s insertString:@" " atIndex:pos];
    }

    return s;
}

- (NSData *)computeSignatureFromKey1:(uint32_t)key1 key2:(uint32_t)key2 key3:(uint8_t *)key3
{
    unsigned char md5[CC_MD5_DIGEST_LENGTH];
    CC_MD5_CTX ctx = {0};

    key1 = OSSwapHostToBigInt32(key1);
    key2 = OSSwapHostToBigInt32(key2);

    CC_MD5_Init(&ctx);
    CC_MD5_Update(&ctx, &key1, sizeof(key1));
    CC_MD5_Update(&ctx, &key2, sizeof(key2));
    CC_MD5_Update(&ctx, key3, 8);
    CC_MD5_Final(md5, &ctx);
    
    return [[NSData alloc] initWithBytes:md5 length:CC_MD5_DIGEST_LENGTH];
}

- (void)sendHeaders
{
    // Generate keys and challenge
    uint32_t key1, key2;
    uint8_t key3[8];

    NSString *s1 = [self generateKeyString:&key1];
    NSString *s2 = [self generateKeyString:&key2];
    for (int i = 0; i < 8; i++)
        key3[i] = arc4random() % 255;
    
    _challenge = [self computeSignatureFromKey1:key1 key2:key2 key3:key3];
    
    NSMutableString * header = [NSMutableString string];
    [header appendString:@"GET /socket.io/websocket HTTP/1.1\r\n"];
    [header appendString:@"Upgrade: WebSocket\r\n"];
    [header appendString:@"Connection: Upgrade\r\n"];
    [header appendFormat:@"Host: %@:%u\r\n", _hostName, _port];
    [header appendFormat:@"Origin: http://%@:%u\r\n", _hostName, _port];
    
    if ([_delegate respondsToSelector:@selector(additionalHeaders)]) {
        NSDictionary * headers = [_delegate additionalHeaders];
        for (NSString * key in headers){
            [header appendFormat:@"%@: %@\r\n", key, [headers objectForKey:key]];
        }
    }
    
    [header appendFormat:@"Sec-WebSocket-Key1: %@\r\n", s1];
    [header appendFormat:@"Sec-WebSocket-Key2: %@\r\n", s2];
    [header appendString:@"\r\n"];

    NSData * headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    
    [self send:[headerData bytes] length:[headerData length]];
    [self send:key3 length:sizeof(key3)];
}

@end
