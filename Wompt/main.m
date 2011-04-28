//
//  main.m
//  Wompt
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Wompt.h"

int main (int argc, const char * argv[])
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSArray * args = [[NSProcessInfo processInfo] arguments];
    if (args == NULL || [args count] != 2) {
        NSLog(@"usage: wompt <ChannelToJoin>");
        exit(1);
    }
    
    Wompt * myWompt = [[Wompt alloc] initWithChannel:[args objectAtIndex:1]];
    [myWompt run];
        
    [myWompt release];
    [pool drain];
    return 0;
}
