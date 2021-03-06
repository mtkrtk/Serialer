#import "AppDelegate.h"

static NSString *userDefaultsBaudKey = @"SerialerBaudRate";

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;

@end

@implementation AppDelegate
{
    Serial *serial;
    NSTextStorage *storage;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    storage = self.outputView.textStorage;
    void (^block)(NSNotification *) = ^(NSNotification *note){
        NSSize size = [self.scrollView frame].size;
        size.height -= 5;
        size.width -= 5;
        self.outputView.minSize = size;
    };
    [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
                                                      object:self.scrollView queue:nil usingBlock:block];
    block(nil);
    
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *baudratesTxt = [NSString stringWithContentsOfFile:[bundle pathForResource:@"BaudRates" ofType:@"txt"]
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
    NSArray *baudrates = [baudratesTxt componentsSeparatedByString:@"\n"];
    [self.baudPopUp addItemsWithObjectValues:baudrates];
    self.baudPopUp.numberOfVisibleItems = baudrates.count;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSInteger initialBaud = [userDefaults integerForKey:userDefaultsBaudKey];
    self.baudPopUp.stringValue = [NSString stringWithFormat:@"%ld", initialBaud];
    
    [self search:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:self.baudPopUp.integerValue forKey:userDefaultsBaudKey];
    [userDefaults synchronize];
}

- (IBAction)search:(NSButton *)sender
{
    [_portsBox removeAllItems];
    NSArray *ports = [Serial availableDevices];
    if (ports.count) {
        [_portsBox addItemsWithObjectValues:ports];
        _portsBox.stringValue = ports.lastObject;
    } else {
        _portsBox.stringValue = @"";
    }
}

- (IBAction)send:(NSButton *)sender {
    switch (_sendKindBox.selectedTag) {
        case 0:
        {
            NSData *data = [_sendTextField.stringValue dataUsingEncoding:NSUTF8StringEncoding];
            [serial sendData:data];
        }
            break;
            
        case 1:
        {
            uint8_t byte = _sendTextField.integerValue;
            NSData *data = [NSData dataWithBytes:&byte length:1];
            [serial sendData:data];
        }
            break;
            
        case 2:
        {
            NSData *data = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
            [serial sendData:data];
        }
            
        default:
            break;
    }
}

- (void)printTextView:(id)str
{
    @synchronized(_outputView) {
        _outputView.editable = YES;
        [storage beginEditing];
        @try {
            if ([str isKindOfClass:[NSAttributedString class]]) {
                [storage appendAttributedString:str];
            } else {
                [storage appendAttributedString:[[NSAttributedString alloc] initWithString:str]];
            }
            [self.outputView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
        } @finally {
            [storage endEditing];
            _outputView.editable = NO;
        }
    }
}

- (IBAction)startOrStop:(NSButton *)sender
{
    if ([sender.title isEqualToString:@"Start"]) {
        NSInteger baud = self.baudPopUp.integerValue;
        if (baud == 0) {
            return;
        }
        
        @synchronized(_outputView) {
            NSTextStorage *textStorage = [_outputView textStorage];
            [textStorage beginEditing];
            NSAttributedString *str = [[NSAttributedString alloc] initWithString:@""];
            [textStorage setAttributedString:str];
            [textStorage endEditing];
        }
        
        @try {
            serial = [[Serial alloc] initWithBSDPath:_portsBox.stringValue];
            [serial openWithBaud:baud delegate:self];
            sender.title = @"Stop";
            sender.state = NSOffState;
            _baudPopUp.hidden = YES;
        }
        @catch (NSException *exception) {
            if ([exception.name isEqualToString:SerialException]) {
                NSMutableAttributedString *err = [[NSMutableAttributedString alloc]
                                                  initWithString:exception.reason];
                [err setAttributes:@{NSForegroundColorAttributeName: [NSColor redColor]}
                             range:NSMakeRange(0, err.length)];
                [self printTextView:err];
            } else {
                @throw exception;
            }
        }
    } else {
        [serial close];
        serial = nil;
        sender.title = @"Start";
        sender.state = NSOnState;
        _baudPopUp.hidden = NO;
    }
}

- (IBAction)clear:(NSButton *)sender
{
    @synchronized(_outputView) {
        NSTextStorage *textStorage = [_outputView textStorage];
        [textStorage beginEditing];
        NSAttributedString *str = [[NSAttributedString alloc] initWithString:@""];
        [textStorage setAttributedString:str];
        [textStorage endEditing];
    }
}

- (void)readData:(NSData *)data
{
    @try {
        switch (_modePopUp.selectedTag) {
            case 0:
            {
                NSString *str = [[NSString alloc] initWithData:data
                                                      encoding:NSUTF8StringEncoding];
                if (str) {
                    [self printTextView:str];
                }
            }
                break;
                
            case 1:
            {
                const uint8_t *bytes = data.bytes;
                for (int i = 0; i < data.length; i++) {
                    [self printTextView:[NSString stringWithFormat:@"%u\n", bytes[i]]];
                }
            }
                break;
                
            case 2:
            {
                const int8_t *bytes = data.bytes;
                for (int i = 0; i < data.length; i++) {
                    [self printTextView:[NSString stringWithFormat:@"%d\n", bytes[i]]];
                }
            }
                break;
                
            default:
                break;
        }
    }
    @catch (NSException *exception) {
        if (! [exception.name isEqualToString:NSInvalidArgumentException]) {
            @throw exception;
        }
    }
}

@end
