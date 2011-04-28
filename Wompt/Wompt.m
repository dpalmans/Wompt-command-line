//
//  Wompt.m
//  Wompt
//
//  Created by Denis Palmans on 4/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "Wompt.h"
#import "NSDictionary+BSJSONAdditions.h"
#include <regex.h>

/* Define some local prototypes. */
void help(CDKENTRY *entry);
static BINDFN_PROTO(tabCB);


#define WomptPrint(args...) printf("%s\n", [[NSString stringWithFormat:args] UTF8String])

@implementation Wompt
             
- (id)initWithChannel:(NSString *)channel
{
    self = [super init];
    if (self) {
        _channel = [channel retain];
        _channelURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://wompt.com/chat/%@", _channel]];

        _formatter = [[NSDateFormatter alloc] init];
        [_formatter setDateFormat:@"hh:mm:ss"];
        
        _userlist = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [_womptConnection release];
    [_connectionID release];
    [_connectorID release];
    [_channel release];
    [_formatter release];
    [_userlist release];
    [super dealloc];
}

- (void)connect
{
#if 0
    // Request this chat page to get a connector_id.
    NSURLRequest * request = [NSURLRequest requestWithURL:_channelURL];
    NSData * data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString * html = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    
    // Find the connector_id in the resulting html
    regex_t re;
    regmatch_t * matches = malloc(2 * sizeof(regmatch_t));

    regcomp(&re, "connector_id  = '(.*)',", REG_EXTENDED|REG_NEWLINE);
    regexec(&re, [html UTF8String], re.re_nsub + 1, matches, 0);        

    _connectorID = [[html substringWithRange:NSMakeRange(matches[1].rm_so, matches[1].rm_eo - matches[1].rm_so)] retain];
    free(matches);
    regfree(&re);
#else
    // Use the reauthenticate method to get a connector_id.
    NSURL * url = [NSURL URLWithString:@"http://wompt.com/re-authenticate"];
    NSURLRequest * request = [NSURLRequest requestWithURL:url];
    NSData * data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString * html = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];

    NSDictionary * dict = [NSDictionary dictionaryWithJSONString:html];
    _connectorID = [[dict objectForKey:@"connector_id"] retain];
#endif
    
    // Connect!
    _womptConnection = [[SocketIOConnection alloc] initWithHost:@"wompt.com" port:80 delegate:self];
}

- (NSDictionary *)additionalHeaders
{
    return nil;
    /*
    // Get cookies for our channel url
    NSArray * cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:_channelURL];
    return [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
    */
}

- (void)gotConnectionID:(NSString *)connectionID
{
    // We're connected, try to join the channel
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"join", @"action",
                           @"chat", @"namespace",
                           _channel, @"channel",
                           _connectorID, @"connector_id", nil];
    [_womptConnection sendDict:dict];

    // Save our connectionID to indicate we're connected
    _connectionID = [connectionID retain];

//    NSLog(@"connectionID: %@", _connectionID);
//    NSLog(@"connectorID: %@", _connectorID);    
}

- (void)printUserList
{
    cleanCDKSwindow(userListWindow);

    for (NSString * user in _userlist) {        
        jumpToLineCDKSwindow(userListWindow, BOTTOM);
        addCDKSwindow (userListWindow, (char *)[user UTF8String], BOTTOM);
    }
}

- (void)printMessage:(NSString *)message
{
    // sprintf (temp, "Command: </R>%s", command);
    jumpToLineCDKSwindow(chatWindow, BOTTOM);
    addCDKSwindow (chatWindow, (char *)[message UTF8String], BOTTOM);   
}

- (void)gotJSONMessage:(NSDictionary *)dict
{
    NSString * action = [dict objectForKey:@"action"];
    if ([action isEqualToString:@"batch"]) {
        NSArray * messages = [dict objectForKey:@"messages"];
        for (NSDictionary * message in messages) {
            [self gotJSONMessage:message];
        }
    } else if ([action isEqualToString:@"message"]) {
        NSString * name = [[dict objectForKey:@"from"] objectForKey:@"name"];
        NSString * msg = [dict objectForKey:@"msg"];
        NSDate * timestamp = [NSDate dateWithTimeIntervalSince1970:[[dict objectForKey:@"t"] doubleValue]/1000];
        
        NSString * string = [NSString stringWithFormat:@"%@ %@: %@",[_formatter stringFromDate:timestamp], name, msg];
        [self printMessage:string];

    } else if ([action isEqualToString:@"join"]) {
        NSDate * timestamp = [NSDate dateWithTimeIntervalSince1970:[[dict objectForKey:@"t"] doubleValue]/1000];

        NSDictionary * users = [dict objectForKey:@"users"];
        for (NSDictionary * userDict in [users objectEnumerator]) {
            NSString * name = [userDict objectForKey:@"name"];

            [_userlist setObject:userDict forKey:name];
             
            NSString * string = [NSString stringWithFormat:@"</b/24>%@ SYSTEM: Joined %@", [_formatter stringFromDate:timestamp], name];
            [self printMessage:string];
        }
        
        [self printUserList];
    } else if ([action isEqualToString:@"part"]) {
        NSDate * timestamp = [NSDate dateWithTimeIntervalSince1970:[[dict objectForKey:@"t"] doubleValue]/1000];
        
        NSDictionary * users = [dict objectForKey:@"users"];
        for (NSDictionary * userDict in [users objectEnumerator]) {
            NSString * name = [userDict objectForKey:@"name"];
            
            [_userlist removeObjectForKey:name];
            
            NSString * string = [NSString stringWithFormat:@"</b/24>%@ SYSTEM: Left %@", [_formatter stringFromDate:timestamp], name];
            [self printMessage:string];
        }
        
        [self printUserList];
    }
}

- (void)gotUnkownMessage:(uint8_t *)message length:(size_t)len
{
    NSLog(@"Got Unkown Message: %s", message);
}


- (void)sendMessage:(NSString *)message
{
    if (_connectionID == nil || _channel == nil) {
        NSLog(@"Unable to send message - not in channel yet");
        return;
    }
        
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           _channel, @"chan",
                           @"post", @"action",
                           message, @"msg", nil];
    [_womptConnection sendDict:dict];
}
                     
                     

//============================
  
- (void)run
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    WINDOW *cursesWin = NULL;
    CDKENTRY *messageEntry;
    NSString * string;
    
    cursesWin = initscr();
    cdkscreen = initCDKScreen(cursesWin);
    initCDKColor();
    
    // Create the chat window.
    string = [NSString stringWithFormat:@"<C></b/24>%@", _channel];
    chatWindow = newCDKSwindow(cdkscreen, LEFT, TOP, -5, -30, (char *)[string UTF8String], 1000, TRUE, FALSE);
    
    // Create the user list window
    userListWindow = newCDKSwindow(cdkscreen, RIGHT, TOP, -5, 30, "<C></b/24>Users", 1000, TRUE, FALSE);
        
    /* Create the text entry field. */
    messageEntry = newCDKEntry (cdkscreen, CENTER, BOTTOM,
                                0, "</b/24> >", A_BOLD|COLOR_PAIR(8), COLOR_PAIR(24)|' ',
                                vMIXED, 0, 1, 512, TRUE, FALSE);
    
    /* Create the key bindings. */
    bindCDKObject(vENTRY, messageEntry, KEY_TAB, tabCB, chatWindow);
    
    // Connect to the channel
    [self connect];
    
    /* Draw the screen. */
    refreshCDKScreen(cdkscreen);
        
    while(1) {
        /* Get the command. */
        drawCDKEntry (messageEntry, ObjOf(messageEntry)->box);
        char * entry = activateCDKEntry(messageEntry, 0);
        if (entry == NULL || entry[0] == '\0')
            continue;
        
        NSString * command = [NSString stringWithUTF8String:entry];        
        if ([command caseInsensitiveCompare:@"Q"] == NSOrderedSame ||
            messageEntry->exitType == vESCAPE_HIT) {
            
            destroyCDKEntry(messageEntry);
            destroyCDKSwindow(chatWindow);
            destroyCDKSwindow(userListWindow);
            destroyCDKScreen(cdkscreen);
            endCDK();
            
            return;
        } else if ([command caseInsensitiveCompare:@"/clear"] == NSOrderedSame) {
            cleanCDKSwindow(chatWindow);
            cleanCDKEntry(messageEntry);
        } else if ([command caseInsensitiveCompare:@"/help"] == NSOrderedSame) {
            help(messageEntry);
            
            cleanCDKEntry(messageEntry);
            eraseCDKEntry(messageEntry);
        } else {            
            [self sendMessage:command];            
            cleanCDKEntry(messageEntry);
        }
        
        [pool drain];
        pool = [[NSAutoreleasePool alloc] init];
    }

    [pool drain];
}

@end


static int tabCB(EObjectType cdktype GCC_UNUSED, void *object, void *clientData, chtype key GCC_UNUSED)
{
    CDKSWINDOW *swindow = (CDKSWINDOW *)clientData;
    CDKENTRY *entry     = (CDKENTRY *)object;
    
    activateCDKSwindow(swindow, 0);    
    drawCDKEntry (entry, ObjOf(entry)->box);
    
    return FALSE;
}

void help (CDKENTRY *entry)
{
    char *mesg[14];
    
    /* Create the help message. */
    mesg[0]  = "<C></B/29>Help";
    mesg[1]  = "";
    mesg[2]  = "</B/24>When in the command line.";
    mesg[3]  = "<B=Tab       > Switches to the chat window.";
    mesg[4]  = "<B=help      > Displays this help window.";
    mesg[5]  = "";
    mesg[6]  = "</B/24>When in the chat window.";
    mesg[7]  = "<B=s or S    > Saves the contents of the window to a file.";
    mesg[8]  = "<B=Up Arrow  > Scrolls up one line.";
    mesg[9]  = "<B=Down Arrow> Scrolls down one line.";
    mesg[10] = "<B=Page Up   > Scrolls back one page.";
    mesg[11] = "<B=Page Down > Scrolls forward one page.";
    mesg[12] = "<B=Tab/Escape> Returns to the command line.";
    mesg[13] = "";
    popupLabel(ScreenOf(entry), mesg, 14);
}
