#import "OmniISHRuntime.h"
#import "app/ISHShellExecutor.h"

#if TARGET_OS_IOS
#import "app/Terminal.h"
#import "app/TerminalView.h"
#endif

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <pthread.h>
#include <resolv.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define ISH_INTERNAL 1
#include "fs/devices.h"
#include "fs/fake.h"
#include "fs/path.h"
#include "fs/real.h"
#include "fs/sock.h"
#include "fs/tty.h"
#include "kernel/calls.h"
#include "kernel/errno.h"
#include "kernel/fs.h"
#include "kernel/init.h"
#include "kernel/task.h"
#include "tools/fakefs.h"

NSErrorDomain const OmniISHRuntimeErrorDomain = @"cn.com.omnimind.OmniBot.iSHRuntime";

static NSString *const OmniISHGuestWorkspacePath = @"/workspace";
static NSString *const OmniISHRootCompletionMarkerName = @".omnibot-rootfs-complete";
static const NSUInteger OmniISHMaximumArgumentBytes = 64 * 1024;
static const NSUInteger OmniISHMaximumEnvironmentBytes = 256 * 1024;
static const NSTimeInterval OmniISHExecutionCleanupPollInterval = 0.020;
static const NSTimeInterval OmniISHExecutionWatchdogGrace = 2;
static const NSUInteger OmniISHMaximumPendingTerminalOutputBytes = 1024 * 1024;
static const NSUInteger OmniISHMaximumTerminalOutputDeliveryBytes = 64 * 1024;
static const NSUInteger OmniISHMaximumPendingTerminalInputBytes = 1024 * 1024;
static const NSUInteger OmniISHMaximumTerminalInputChunkBytes = 1024;
static const NSTimeInterval OmniISHTerminalInputRetryInterval = 0.005;
static const NSTimeInterval OmniISHTerminalInputRetryLimit = 5;

@interface OmniISHCommandResult ()
@property(nonatomic, readwrite) int exitCode;
@property(nonatomic, readwrite) int processIdentifier;
@property(nonatomic, readwrite, copy) NSString *standardOutput;
@property(nonatomic, readwrite, copy) NSString *standardError;
@property(nonatomic, readwrite) NSTimeInterval duration;
@property(nonatomic, readwrite, nullable) NSError *error;
@end

@implementation OmniISHCommandResult
@end

@class OmniISHInteractiveTerminalContext;

@interface OmniISHInteractiveTerminalContext : NSObject {
    struct tty *_terminal;
    dispatch_queue_t _inputQueue;
    dispatch_group_t _inputGroup;
    NSUInteger _pendingInputBytes;
    BOOL _acceptsInput;

    NSCondition *_outputCondition;
    NSMutableData *_pendingOutputData;
    NSUInteger _inFlightOutputBytes;
    BOOL _acceptsOutput;
    BOOL _outputDeliveryEnabled;
    BOOL _outputDeliveryScheduled;
    uint64_t _nextOutputDeliveryToken;
    uint64_t _activeOutputDeliveryToken;
    BOOL _finishRequested;
    BOOL _exitCallbackScheduled;
    int _finalExitCode;
    NSError *_finalError;
}

@property(nonatomic, readonly) NSUUID *identifier;
@property(nonatomic) int guestProcessIdentifier;
@property(nonatomic) uint64_t guestExecutionContext;
@property(nonatomic, copy, nullable) OmniISHTerminalOutputHandler outputHandler;
@property(nonatomic, copy, nullable) OmniISHTerminalStartedHandler startedHandler;
@property(nonatomic, copy, nullable) OmniISHTerminalExitHandler exitHandler;
@property(nonatomic) BOOL processExited;
@property(nonatomic) BOOL cleanupStarted;
@property(nonatomic) BOOL cleanupPollScheduled;
@property(nonatomic) CFAbsoluteTime cleanupDeadline;
@property(nonatomic) BOOL completionScheduled;
@property(nonatomic) BOOL completed;
@property(nonatomic) int waitStatus;
@property(nonatomic, nullable) NSError *forcedError;

#if TARGET_OS_IOS
@property(nonatomic, strong, nullable) Terminal *upstreamTerminal;
@property(nonatomic, strong, nullable) TerminalView *upstreamTerminalView;
#endif

- (instancetype)initWithIdentifier:(NSUUID *)identifier
                       outputHandler:(OmniISHTerminalOutputHandler)outputHandler
                      startedHandler:(OmniISHTerminalStartedHandler)startedHandler
                         exitHandler:(OmniISHTerminalExitHandler)exitHandler;
- (void)attachTerminal:(struct tty *)terminal;
#if TARGET_OS_IOS
- (void)attachTerminal:(struct tty *)terminal upstreamTerminal:(Terminal *)upstreamTerminal;
- (nullable UIView *)makeUpstreamTerminalView;
#endif
- (int)enqueueOutputBytes:(const void *)bytes length:(NSUInteger)length blocking:(BOOL)blocking;
- (void)enqueueInputData:(NSData *)data;
- (void)notifyStarted;
- (void)stopAcceptingIO;
- (void)notifyWhenInputDrainedOnQueue:(dispatch_queue_t)queue block:(dispatch_block_t)block;
- (void)releaseTerminalReference;
- (void)finishOutputWithExitCode:(int)exitCode error:(nullable NSError *)error;
- (void)resizeToColumns:(int)columns rows:(int)rows;

@end

@implementation OmniISHInteractiveTerminalContext

- (instancetype)initWithIdentifier:(NSUUID *)identifier
                       outputHandler:(OmniISHTerminalOutputHandler)outputHandler
                      startedHandler:(OmniISHTerminalStartedHandler)startedHandler
                         exitHandler:(OmniISHTerminalExitHandler)exitHandler {
    self = [super init];
    if (self) {
        _identifier = identifier;
        _outputHandler = [outputHandler copy];
        _startedHandler = [startedHandler copy];
        _exitHandler = [exitHandler copy];
        NSString *queueLabel = [NSString stringWithFormat:@"cn.com.omnimind.OmniBot.iSH.terminal.input.%@",
                                                        identifier.UUIDString];
        _inputQueue = dispatch_queue_create(queueLabel.UTF8String, DISPATCH_QUEUE_SERIAL);
        _inputGroup = dispatch_group_create();
        _acceptsInput = YES;
        _outputCondition = [[NSCondition alloc] init];
        _pendingOutputData = [NSMutableData data];
        _acceptsOutput = YES;
    }
    return self;
}

- (void)attachTerminal:(struct tty *)terminal {
    @synchronized(self) {
        _terminal = terminal;
        terminal->data = (void *)CFBridgingRetain(self);
    }
}

#if TARGET_OS_IOS
- (void)attachTerminal:(struct tty *)terminal upstreamTerminal:(Terminal *)upstreamTerminal {
    @synchronized(self) {
        _terminal = terminal;
        _upstreamTerminal = upstreamTerminal;
    }
    __weak typeof(self) weakSelf = self;
    upstreamTerminal.outputObserver = ^(NSData *data) {
        typeof(self) self = weakSelf;
        if (self != nil) {
            [self enqueueOutputBytes:data.bytes
                              length:data.length
                            blocking:!NSThread.isMainThread];
        }
    };
}

- (UIView *)makeUpstreamTerminalView {
    NSAssert(NSThread.isMainThread, @"The iSH terminal view must be created on the main thread.");

    Terminal *terminal = nil;
    @synchronized(self) {
        if (_upstreamTerminalView != nil) {
            return _upstreamTerminalView;
        }
        terminal = _upstreamTerminal;
    }
    if (terminal == nil) {
        return nil;
    }

    // TerminalView is normally unarchived from iSH's storyboard with a real
    // screen-sized frame before Terminal.webView is attached. Starting it at
    // CGRectZero makes WebKit render its first remote layer at the 10000-point
    // preload size and then scale that layer through a zero-sized viewport,
    // which can leave the first presentation visibly blurred. Preserve iSH's
    // original lifecycle invariant; SwiftUI will apply the final content frame.
    CGRect initialFrame = CGRectMake(0, 0, 1, 1);
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIWindow *keyWindow = nil;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow != nil) {
            initialFrame = keyWindow.bounds;
            break;
        }
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            initialFrame = windowScene.effectiveGeometry.coordinateSpace.bounds;
        }
    }
    TerminalView *terminalView = [[TerminalView alloc] initWithFrame:initialFrame];
    terminalView.canBecomeFirstResponder = YES;
    terminalView.terminal = terminal;

    @synchronized(self) {
        if (_upstreamTerminal != terminal) {
            terminalView.terminal = nil;
            return nil;
        }
        _upstreamTerminalView = terminalView;
    }
    return terminalView;
}
#endif

- (void)scheduleExitIfReadyLocked {
    if (!_finishRequested || !_outputDeliveryEnabled || _outputDeliveryScheduled ||
        _pendingOutputData.length > 0 || _inFlightOutputBytes > 0 || _exitCallbackScheduled) {
        return;
    }

    _exitCallbackScheduled = YES;
    int exitCode = _finalExitCode;
    NSError *error = _finalError;
    OmniISHTerminalExitHandler exitHandler = [_exitHandler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (exitHandler != nil) {
            exitHandler(exitCode, error);
        }
        [self->_outputCondition lock];
        self->_outputHandler = nil;
        self->_startedHandler = nil;
        self->_exitHandler = nil;
        [self->_outputCondition unlock];
    });
}

- (void)scheduleOutputDeliveryLocked {
    if (!_outputDeliveryEnabled || _outputDeliveryScheduled) {
        [self scheduleExitIfReadyLocked];
        return;
    }
    if (_pendingOutputData.length == 0) {
        [self scheduleExitIfReadyLocked];
        return;
    }

    NSUInteger deliveryBytes = MIN(_pendingOutputData.length,
                                   OmniISHMaximumTerminalOutputDeliveryBytes);
    NSData *data = [_pendingOutputData subdataWithRange:NSMakeRange(0, deliveryBytes)];
    [_pendingOutputData replaceBytesInRange:NSMakeRange(0, deliveryBytes)
                                  withBytes:NULL
                                     length:0];
    _inFlightOutputBytes = data.length;
    _outputDeliveryScheduled = YES;
    uint64_t deliveryToken = ++_nextOutputDeliveryToken;
    _activeOutputDeliveryToken = deliveryToken;
    OmniISHTerminalOutputHandler outputHandler = [_outputHandler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        OmniISHTerminalOutputAcknowledgement acknowledge = ^{
            [self->_outputCondition lock];
            if (!self->_outputDeliveryScheduled ||
                self->_activeOutputDeliveryToken != deliveryToken) {
                [self->_outputCondition unlock];
                return;
            }
            self->_inFlightOutputBytes = 0;
            self->_outputDeliveryScheduled = NO;
            [self->_outputCondition broadcast];
            [self scheduleOutputDeliveryLocked];
            [self->_outputCondition unlock];
        };
        if (outputHandler != nil) {
            outputHandler(data, acknowledge);
        } else {
            acknowledge();
        }
    });
}

- (int)enqueueOutputBytes:(const void *)bytes length:(NSUInteger)length blocking:(BOOL)blocking {
    if (length == 0) {
        return 0;
    }

    const uint8_t *cursor = bytes;
    NSUInteger remaining = length;
    [_outputCondition lock];
    if (!blocking) {
        NSUInteger bufferedBytes = _pendingOutputData.length + _inFlightOutputBytes;
        NSUInteger availableBytes = bufferedBytes >= OmniISHMaximumPendingTerminalOutputBytes
            ? 0
            : OmniISHMaximumPendingTerminalOutputBytes - bufferedBytes;
        if (!_acceptsOutput) {
            [_outputCondition unlock];
            return _EIO;
        }
        if (remaining > availableBytes) {
            [_outputCondition unlock];
            return _EAGAIN;
        }
        [_pendingOutputData appendBytes:cursor length:remaining];
        [self scheduleOutputDeliveryLocked];
        [_outputCondition unlock];
        return (int)MIN(length, (NSUInteger)INT_MAX);
    }

    while (remaining > 0) {
        if (!_acceptsOutput) {
            [_outputCondition unlock];
            return _EIO;
        }

        NSUInteger bufferedBytes = _pendingOutputData.length + _inFlightOutputBytes;
        if (bufferedBytes >= OmniISHMaximumPendingTerminalOutputBytes) {
            [_outputCondition wait];
            continue;
        }

        NSUInteger availableBytes = OmniISHMaximumPendingTerminalOutputBytes - bufferedBytes;
        NSUInteger acceptedBytes = MIN(remaining, availableBytes);
        [_pendingOutputData appendBytes:cursor length:acceptedBytes];
        cursor += acceptedBytes;
        remaining -= acceptedBytes;
        [self scheduleOutputDeliveryLocked];
    }
    [_outputCondition unlock];
    return (int)MIN(length, (NSUInteger)INT_MAX);
}

- (void)enqueueInputData:(NSData *)data {
    if (data.length == 0) {
        return;
    }

    @synchronized(self) {
        if (!_acceptsInput || _terminal == NULL ||
            data.length > OmniISHMaximumPendingTerminalInputBytes -
                MIN(_pendingInputBytes, OmniISHMaximumPendingTerminalInputBytes)) {
            return;
        }
        _pendingInputBytes += data.length;
        dispatch_group_enter(_inputGroup);
    }

    dispatch_async(_inputQueue, ^{
        const char *bytes = data.bytes;
        NSUInteger offset = 0;
        CFAbsoluteTime retryDeadline = CFAbsoluteTimeGetCurrent() + OmniISHTerminalInputRetryLimit;
        while (offset < data.length) {
            struct tty *terminal = NULL;
            BOOL acceptsInput = NO;
            @synchronized(self) {
                terminal = self->_terminal;
                acceptsInput = self->_acceptsInput;
            }
            if (!acceptsInput || terminal == NULL) {
                break;
            }

            NSUInteger requestedBytes = MIN(OmniISHMaximumTerminalInputChunkBytes, data.length - offset);
            ssize_t acceptedBytes = tty_input(terminal, bytes + offset, requestedBytes, false);
            if (acceptedBytes > 0) {
                offset += (NSUInteger)acceptedBytes;
                retryDeadline = CFAbsoluteTimeGetCurrent() + OmniISHTerminalInputRetryLimit;
                continue;
            }
            if (acceptedBytes != _EAGAIN && acceptedBytes != _EINTR) {
                break;
            }
            if (CFAbsoluteTimeGetCurrent() >= retryDeadline) {
                break;
            }
            usleep((useconds_t)(OmniISHTerminalInputRetryInterval * 1000 * 1000));
        }

        @synchronized(self) {
            self->_pendingInputBytes -= MIN(self->_pendingInputBytes, data.length);
        }
        dispatch_group_leave(self->_inputGroup);
    });
}

- (void)notifyStarted {
    int processIdentifier = self.guestProcessIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{
        OmniISHTerminalStartedHandler startedHandler = self.startedHandler;
        self.startedHandler = nil;
        if (startedHandler != nil) {
            startedHandler(processIdentifier, nil);
        }

        [self->_outputCondition lock];
        self->_outputDeliveryEnabled = YES;
        [self scheduleOutputDeliveryLocked];
        [self->_outputCondition unlock];
    });
}

- (void)stopAcceptingIO {
    @synchronized(self) {
        _acceptsInput = NO;
    }
    [_outputCondition lock];
    _acceptsOutput = NO;
    [_outputCondition broadcast];
    [_outputCondition unlock];
}

- (void)notifyWhenInputDrainedOnQueue:(dispatch_queue_t)queue block:(dispatch_block_t)block {
    dispatch_group_notify(_inputGroup, queue, block);
}

- (void)releaseTerminalReference {
    struct tty *terminal = NULL;
#if TARGET_OS_IOS
    Terminal *upstreamTerminal = nil;
    TerminalView *upstreamTerminalView = nil;
#endif
    @synchronized(self) {
        terminal = _terminal;
        _terminal = NULL;
#if TARGET_OS_IOS
        upstreamTerminal = _upstreamTerminal;
        _upstreamTerminal = nil;
        upstreamTerminalView = _upstreamTerminalView;
        _upstreamTerminalView = nil;
#endif
    }

#if TARGET_OS_IOS
    if (upstreamTerminal != nil || upstreamTerminalView != nil) {
        void (^detachUpstreamTerminal)(void) = ^{
            upstreamTerminal.outputObserver = nil;
            upstreamTerminalView.terminal = nil;
            [upstreamTerminal destroy];
        };
        if (NSThread.isMainThread) {
            detachUpstreamTerminal();
        } else {
            dispatch_sync(dispatch_get_main_queue(), detachUpstreamTerminal);
        }
    }
#endif

    if (terminal == NULL) {
        return;
    }

    lock(&ttys_lock);
    tty_release(terminal);
    unlock(&ttys_lock);
}

- (void)finishOutputWithExitCode:(int)exitCode error:(NSError *)error {
    [_outputCondition lock];
    _acceptsOutput = NO;
    _finishRequested = YES;
    _finalExitCode = exitCode;
    _finalError = error;
    [_outputCondition broadcast];
    [self scheduleOutputDeliveryLocked];
    [_outputCondition unlock];
}

- (void)resizeToColumns:(int)columns rows:(int)rows {
    struct tty *terminal = NULL;
    @synchronized(self) {
        if (_acceptsInput) {
            terminal = _terminal;
        }
    }
    if (terminal == NULL) {
        return;
    }

    lock(&terminal->lock);
    tty_set_winsize(terminal, (struct winsize_) {
        .col = (word_t)columns,
        .row = (word_t)rows,
    });
    unlock(&terminal->lock);
}

- (void)dealloc {
    [self stopAcceptingIO];
    [self releaseTerminalReference];
}

@end

#if !TARGET_OS_IOS
static int OmniISHInteractiveTerminalWrite(struct tty *terminal,
                                           const void *bytes,
                                           size_t length,
                                           bool blocking) {
    OmniISHInteractiveTerminalContext *context = (__bridge OmniISHInteractiveTerminalContext *)terminal->data;
    if (context == nil) {
        return _EIO;
    }
    return [context enqueueOutputBytes:bytes length:length blocking:blocking];
}

static void OmniISHInteractiveTerminalCleanup(struct tty *terminal) {
    void *retainedContext = terminal->data;
    terminal->data = NULL;
    if (retainedContext != NULL) {
        CFRelease(retainedContext);
    }
}

static const struct tty_driver_ops OmniISHInteractiveTerminalDriverOperations = {
    .write = OmniISHInteractiveTerminalWrite,
    .cleanup = OmniISHInteractiveTerminalCleanup,
};

static struct tty_driver OmniISHInteractiveTerminalDriver = {
    .ops = &OmniISHInteractiveTerminalDriverOperations,
};
#endif

@interface OmniISHRuntime ()
+ (void)handleProcessExitWithIdentifier:(int)processIdentifier
                                  status:(int)status
                        executionContext:(uint64_t)executionContext;
+ (void)handleInteractiveTerminalExitWithIdentifier:(int)processIdentifier
                                              status:(int)status
                                    executionContext:(uint64_t)executionContext;
@end

static dispatch_queue_t OmniISHRuntimeQueue;
static char OmniISHRuntimeQueueSpecificKey;
static NSMutableDictionary<NSUUID *, OmniISHInteractiveTerminalContext *> *OmniISHInteractiveTerminals;
static NSMutableDictionary<NSNumber *, NSUUID *> *OmniISHInteractiveTerminalIdentifiersByPID;
static BOOL OmniISHReady;
static BOOL OmniISHPreparing;
static BOOL OmniISHCoreBootStarted;
static BOOL OmniISHCoreBootFailed;

static NSError *OmniISHMakeError(OmniISHRuntimeError code, NSString *description) {
    return [NSError errorWithDomain:OmniISHRuntimeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static int OmniISHNormalizedExitCode(int status) {
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return status;
}

static BOOL OmniISHStringContainsNUL(NSString *value) {
    unichar nul = 0;
    NSString *nulString = [NSString stringWithCharacters:&nul length:1];
    return [value rangeOfString:nulString].location != NSNotFound;
}

static uint64_t OmniISHExecutionContextFromIdentifier(NSUUID *identifier) {
    uuid_t bytes = {0};
    [identifier getUUIDBytes:bytes];
    uint64_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value == 0 ? 1 : value;
}

static NSData *_Nullable OmniISHArgumentData(NSArray<NSString *> *arguments, NSError **errorOut) {
    NSMutableData *data = [NSMutableData data];
    const uint8_t zero = 0;
    for (NSString *argument in arguments) {
        NSData *argumentData = [argument dataUsingEncoding:NSUTF8StringEncoding];
        if (argumentData == nil || OmniISHStringContainsNUL(argument) ||
            data.length + argumentData.length + 2 > OmniISHMaximumArgumentBytes) {
            if (errorOut != NULL) {
                *errorOut = OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                             @"The Alpine command exceeds the 64 KiB UTF-8 argument limit.");
            }
            return nil;
        }
        [data appendData:argumentData];
        [data appendBytes:&zero length:1];
    }
    [data appendBytes:&zero length:1];
    return data;
}

static NSData *_Nullable OmniISHEnvironmentData(NSDictionary<NSString *, NSString *> *environment,
                                                 NSError **errorOut) {
    NSMutableData *data = [NSMutableData data];
    const uint8_t zero = 0;
    for (NSString *key in [[environment allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *value = environment[key];
        if (key.length == 0 || [key rangeOfString:@"="].location != NSNotFound ||
            OmniISHStringContainsNUL(key) || OmniISHStringContainsNUL(value)) {
            if (errorOut != NULL) {
                *errorOut = OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                             @"The Alpine command environment contains an invalid key or value.");
            }
            return nil;
        }
        NSData *entryData = [[NSString stringWithFormat:@"%@=%@", key, value]
            dataUsingEncoding:NSUTF8StringEncoding];
        if (entryData == nil || data.length + entryData.length + 2 > OmniISHMaximumEnvironmentBytes) {
            if (errorOut != NULL) {
                *errorOut = OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                             @"The Alpine command environment exceeds the 256 KiB limit.");
            }
            return nil;
        }
        [data appendData:entryData];
        [data appendBytes:&zero length:1];
    }
    [data appendBytes:&zero length:1];
    return data;
}

static void OmniISHConfigureDNS(void) {
    struct __res_state resolver = {0};
    NSMutableString *configuration = [NSMutableString string];
    if (res_ninit(&resolver) == 0) {
        union res_sockaddr_union servers[NI_MAXSERV];
        int serverCount = res_getservers(&resolver, servers, NI_MAXSERV);
        char address[NI_MAXHOST];
        for (int index = 0; index < serverCount; index += 1) {
            union res_sockaddr_union server = servers[index];
            if (server.sin.sin_len == 0) {
                continue;
            }
            int result = getnameinfo((struct sockaddr *)&server.sin,
                                     server.sin.sin_len,
                                     address,
                                     sizeof(address),
                                     NULL,
                                     0,
                                     NI_NUMERICHOST);
            if (result == 0) {
                [configuration appendFormat:@"nameserver %s\n", address];
            }
        }
        res_nclose(&resolver);
    }
    if (configuration.length == 0) {
        [configuration appendString:@"nameserver 1.1.1.1\nnameserver 8.8.8.8\n"];
    }

    struct fd *file = generic_open("/etc/resolv.conf", O_WRONLY_ | O_CREAT_ | O_TRUNC_, 0644);
    if (!IS_ERR(file)) {
        NSData *data = [configuration dataUsingEncoding:NSUTF8StringEncoding];
        file->ops->write(file, data.bytes, data.length);
        fd_close(file);
    }
}

static void OmniISHRootImportProgress(void *cookie, double progress, const char *message, bool *cancelOut) {
    (void)cancelOut;
    OmniISHProgressHandler handler = (__bridge OmniISHProgressHandler)cookie;
    if (handler == nil) {
        return;
    }
    NSString *progressMessage = message == NULL ? @"" : [NSString stringWithUTF8String:message];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(progress, progressMessage ?: @"");
    });
}

static void OmniISHProcessExitHook(struct task *task, int status) {
    if (task == NULL || task->group == NULL || task->group->leader == NULL) {
        return;
    }
    struct task *leader = task->group->leader;
    struct task *parent = leader->parent;
    if (parent == NULL || parent->pid != 1) {
        return;
    }
    int processIdentifier = leader->pid;
    uint64_t executionContext = leader->group->fs_context;
    int waitStatus = task->group->doing_group_exit
        ? (int)task->group->group_exit_code
        : (int)leader->exit_code;
    if (waitStatus == 0 && status != 0) {
        waitStatus = status;
    }
    dispatch_async(OmniISHRuntimeQueue, ^{
        [OmniISHRuntime handleProcessExitWithIdentifier:processIdentifier
                                                  status:waitStatus
                                        executionContext:executionContext];
    });
}

static void OmniISHKillExecutionProcesses(uint64_t executionContext) {
    if (executionContext == 0) {
        return;
    }
    struct siginfo_ signalInfo = SIGINFO_NIL;
    lock(&pids_lock);
    for (int processIdentifier = 2; processIdentifier <= MAX_PID; processIdentifier += 1) {
        struct task *task = pid_get_task((dword_t)processIdentifier);
        if (task == NULL || !task_is_leader(task) || task->group == NULL ||
            task->group->fs_context != executionContext) {
            continue;
        }
        send_signal(task, SIGKILL_, signalInfo);
        // send_signal() intentionally ignores a signal that is already pending.
        // Cleanup polls must still re-poke a task that entered a blocking host
        // syscall after the first poke, otherwise e.g. BusyBox sleep can keep a
        // pending SIGKILL indefinitely.
        if (task->thread != (pthread_t)0) {
            pthread_kill(task->thread, SIGUSR1);
        }
        lock(&task->waiting_cond_lock);
        if (task->waiting_cond != NULL) {
            notify(task->waiting_cond);
        }
        unlock(&task->waiting_cond_lock);
    }
    unlock(&pids_lock);
}

static NSUInteger OmniISHExecutionProcessCount(uint64_t executionContext) {
    if (executionContext == 0) {
        return 0;
    }
    NSUInteger count = 0;
    lock(&pids_lock);
    for (int processIdentifier = 2; processIdentifier <= MAX_PID; processIdentifier += 1) {
        struct task *task = pid_get_task_zombie((dword_t)processIdentifier);
        if (task != NULL && task_is_leader(task) && task->group != NULL &&
            task->group->fs_context == executionContext) {
            count += 1;
        }
    }
    unlock(&pids_lock);
    return count;
}

static void OmniISHReapGuestProcess(int processIdentifier) {
    struct task *savedCurrent = current;
    lock(&pids_lock);
    struct task *initTask = pid_get_task(1);
    unlock(&pids_lock);
    if (initTask == NULL) {
        return;
    }
    current = initTask;
    (void)sys_waitpid((pid_t_)processIdentifier, 0, 1);
    current = savedCurrent;
}

static void OmniISHReapExecutionZombies(uint64_t executionContext) {
    if (executionContext == 0) {
        return;
    }
    NSMutableArray<NSNumber *> *processIdentifiers = [NSMutableArray array];
    lock(&pids_lock);
    struct task *initTask = pid_get_task(1);
    if (initTask != NULL) {
        for (int processIdentifier = 2; processIdentifier <= MAX_PID; processIdentifier += 1) {
            struct task *task = pid_get_task_zombie((dword_t)processIdentifier);
            if (task == NULL || !task_is_leader(task) || task->group == NULL ||
                task->group->fs_context != executionContext || task->parent != initTask || !task->zombie) {
                continue;
            }
            [processIdentifiers addObject:@(processIdentifier)];
        }
    }
    unlock(&pids_lock);

    for (NSNumber *processIdentifier in processIdentifiers) {
        OmniISHReapGuestProcess(processIdentifier.intValue);
    }
}

static void OmniISHDestroyUnstartedGuestTask(struct task *task) {
    if (task == NULL || task->group == NULL) {
        return;
    }

    lock(&pids_lock);
    task->exiting = true;
    unlock(&pids_lock);

    if (task->mm != NULL) {
        mm_release(task->mm);
        task->mm = NULL;
    }
    if (task->files != NULL) {
        fdtable_release(task->files);
        task->files = NULL;
    }
    if (task->fs != NULL) {
        fs_info_release(task->fs);
        task->fs = NULL;
    }

    lock(&pids_lock);
    if (task->sighand != NULL) {
        sighand_release(task->sighand);
        task->sighand = NULL;
    }
    struct tgroup *group = task->group;
    list_remove(&task->group_links);
    cond_destroy(&group->child_exit);
    cond_destroy(&group->stopped_cond);
    task_leave_session(task);
    list_remove(&group->pgroup);
    free(group);
    cond_destroy(&task->pause);
    cond_destroy(&task->ptrace.cond);
    task_destroy(task);
    unlock(&pids_lock);
}

static void OmniISHBestEffortCleanup(uint64_t executionContext, NSUInteger attemptsRemaining) {
    OmniISHKillExecutionProcesses(executionContext);
    OmniISHReapExecutionZombies(executionContext);
    if (attemptsRemaining == 0 || OmniISHExecutionProcessCount(executionContext) == 0) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   OmniISHRuntimeQueue, ^{
        OmniISHBestEffortCleanup(executionContext, attemptsRemaining - 1);
    });
}

static void OmniISHScheduleInteractiveTerminalCompletion(OmniISHInteractiveTerminalContext *context) {
    if (context.completionScheduled) {
        return;
    }
    context.completionScheduled = YES;
    context.completed = YES;
    [context stopAcceptingIO];

    [OmniISHInteractiveTerminals removeObjectForKey:context.identifier];
    NSUUID *mappedIdentifier = OmniISHInteractiveTerminalIdentifiersByPID[@(context.guestProcessIdentifier)];
    if ([mappedIdentifier isEqual:context.identifier]) {
        [OmniISHInteractiveTerminalIdentifiersByPID removeObjectForKey:@(context.guestProcessIdentifier)];
    }

    OmniISHKillExecutionProcesses(context.guestExecutionContext);
    OmniISHReapExecutionZombies(context.guestExecutionContext);
    int exitCode = OmniISHNormalizedExitCode(context.waitStatus);
    NSError *error = context.forcedError;
    [context notifyWhenInputDrainedOnQueue:OmniISHRuntimeQueue block:^{
        [context releaseTerminalReference];
        [context finishOutputWithExitCode:exitCode error:error];
    }];
}

static void OmniISHFinishInteractiveTerminalAtWatchdog(OmniISHInteractiveTerminalContext *context) {
    if (context.completed) {
        return;
    }
    context.cleanupPollScheduled = NO;
    [context stopAcceptingIO];
    OmniISHKillExecutionProcesses(context.guestExecutionContext);
    OmniISHReapExecutionZombies(context.guestExecutionContext);
    NSUInteger remainingProcessCount = OmniISHExecutionProcessCount(context.guestExecutionContext);
    if (!context.processExited) {
        context.processExited = YES;
        context.waitStatus = SIGKILL;
    }
    NSUUID *mappedIdentifier = OmniISHInteractiveTerminalIdentifiersByPID[@(context.guestProcessIdentifier)];
    if ([mappedIdentifier isEqual:context.identifier]) {
        [OmniISHInteractiveTerminalIdentifiersByPID removeObjectForKey:@(context.guestProcessIdentifier)];
    }
    if (remainingProcessCount > 0 && context.forcedError == nil) {
        context.forcedError = OmniISHMakeError(
            OmniISHRuntimeErrorExecutionFailed,
            @"The interactive terminal's processes did not stop within the 2 second cleanup watchdog."
        );
    }
    OmniISHScheduleInteractiveTerminalCompletion(context);
    if (remainingProcessCount > 0) {
        OmniISHBestEffortCleanup(context.guestExecutionContext, 10);
    }
}

static void OmniISHContinueInteractiveTerminalDrain(OmniISHInteractiveTerminalContext *context) {
    context.cleanupPollScheduled = NO;
    if (context.completed || context.completionScheduled) {
        return;
    }

    OmniISHKillExecutionProcesses(context.guestExecutionContext);
    OmniISHReapExecutionZombies(context.guestExecutionContext);
    if (OmniISHExecutionProcessCount(context.guestExecutionContext) == 0) {
        if (!context.processExited) {
            context.processExited = YES;
            context.waitStatus = SIGKILL;
        }
        OmniISHScheduleInteractiveTerminalCompletion(context);
        return;
    }

    if (CFAbsoluteTimeGetCurrent() >= context.cleanupDeadline) {
        OmniISHFinishInteractiveTerminalAtWatchdog(context);
        return;
    }

    context.cleanupPollScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(OmniISHExecutionCleanupPollInterval * NSEC_PER_SEC)),
                   OmniISHRuntimeQueue, ^{
        OmniISHContinueInteractiveTerminalDrain(context);
    });
}

static void OmniISHStartInteractiveTerminalDrain(OmniISHInteractiveTerminalContext *context) {
    if (context == nil || context.completed) {
        return;
    }
    if (!context.cleanupStarted) {
        context.cleanupStarted = YES;
        [context stopAcceptingIO];
        context.cleanupDeadline = CFAbsoluteTimeGetCurrent() + OmniISHExecutionWatchdogGrace;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(OmniISHExecutionWatchdogGrace * NSEC_PER_SEC)),
                       OmniISHRuntimeQueue, ^{
            OmniISHFinishInteractiveTerminalAtWatchdog(context);
        });
    }
    if (!context.cleanupPollScheduled && !context.completionScheduled) {
        OmniISHContinueInteractiveTerminalDrain(context);
    }
}

static void OmniISHRequestInteractiveTerminalStop(OmniISHInteractiveTerminalContext *context,
                                                  NSError *error) {
    if (context == nil || context.completed) {
        return;
    }
    if (context.forcedError == nil) {
        context.forcedError = error;
    }
    OmniISHStartInteractiveTerminalDrain(context);
}

static int OmniISHChangeGuestWorkingDirectory(NSString *workingDirectory) {
    if (workingDirectory.length == 0 ||
        [workingDirectory lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= MAX_PATH ||
        OmniISHStringContainsNUL(workingDirectory)) {
        return _EINVAL;
    }

    struct statbuf status = {0};
    int error = generic_statat(AT_PWD, workingDirectory.UTF8String, &status, true);
    if (error < 0) {
        return error;
    }
    if (!(status.mode & S_IFDIR)) {
        return _ENOTDIR;
    }

    struct fd *directory = generic_open(workingDirectory.UTF8String, O_RDONLY_, 0);
    if (IS_ERR(directory)) {
        return (int)PTR_ERR(directory);
    }
    fs_chdir(current->fs, directory);
    return 0;
}

static void OmniISHNotifyInteractiveTerminalStartFailure(OmniISHInteractiveTerminalContext *context,
                                                         NSError *error) {
    [context stopAcceptingIO];
    [context releaseTerminalReference];
    OmniISHTerminalStartedHandler startedHandler = context.startedHandler;
    context.startedHandler = nil;
    context.outputHandler = nil;
    context.exitHandler = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (startedHandler != nil) {
            startedHandler(-1, error);
        }
    });
}

@implementation OmniISHRuntime

+ (void)initialize {
    if (self != OmniISHRuntime.class) {
        return;
    }
    OmniISHRuntimeQueue = dispatch_queue_create("cn.com.omnimind.OmniBot.iSH.runtime", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(OmniISHRuntimeQueue,
                                &OmniISHRuntimeQueueSpecificKey,
                                &OmniISHRuntimeQueueSpecificKey,
                                NULL);
    [ISHShellExecutor configureWithExecutionQueue:OmniISHRuntimeQueue];
    OmniISHInteractiveTerminals = [NSMutableDictionary dictionary];
    OmniISHInteractiveTerminalIdentifiersByPID = [NSMutableDictionary dictionary];
}

+ (BOOL)isReady {
    __block BOOL ready = NO;
    dispatch_sync(OmniISHRuntimeQueue, ^{
        ready = OmniISHReady;
    });
    return ready;
}

+ (NSString *)guestWorkspacePath {
    return OmniISHGuestWorkspacePath;
}

+ (void)prepareWithRootFileSystemArchive:(NSURL *)archiveURL
                          expectedSHA256:(NSString *)expectedSHA256
                          stateDirectory:(NSURL *)stateDirectory
                      workspaceDirectory:(NSURL *)workspaceDirectory
                                progress:(OmniISHProgressHandler)progress
                              completion:(OmniISHPreparationCompletion)completion {
    dispatch_async(OmniISHRuntimeQueue, ^{
        if (OmniISHReady) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
            return;
        }
        if (OmniISHCoreBootFailed || (OmniISHCoreBootStarted && !OmniISHPreparing)) {
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorBootFailed,
                                              @"The embedded iSH core failed after boot started. Restart the app before trying again.");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }
        if (OmniISHPreparing) {
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorBootFailed, @"Alpine is already being prepared.");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }
        OmniISHPreparing = YES;

        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSError *fileError = nil;
        if (![fileManager fileExistsAtPath:archiveURL.path]) {
            OmniISHPreparing = NO;
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorRootFileSystemMissing, @"The bundled Alpine root filesystem is missing.");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }
        if (expectedSHA256.length != 64) {
            OmniISHPreparing = NO;
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorRootFileSystemImportFailed,
                                              @"The Alpine root filesystem checksum marker is invalid.");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }

        [fileManager createDirectoryAtURL:stateDirectory.URLByDeletingLastPathComponent
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&fileError];
        if (fileError != nil) {
            OmniISHPreparing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(fileError); });
            return;
        }

        NSURL *metadataURL = [stateDirectory URLByAppendingPathComponent:@"meta.db"];
        NSURL *dataURL = [stateDirectory URLByAppendingPathComponent:@"data" isDirectory:YES];
        NSURL *completionMarkerURL = [stateDirectory URLByAppendingPathComponent:OmniISHRootCompletionMarkerName];
        NSString *completionMarker = [NSString stringWithContentsOfURL:completionMarkerURL
                                                               encoding:NSUTF8StringEncoding
                                                                  error:nil];
        completionMarker = [completionMarker stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL rootIsComplete = [fileManager fileExistsAtPath:metadataURL.path] &&
                              [fileManager fileExistsAtPath:dataURL.path] &&
                              [completionMarker isEqualToString:expectedSHA256];
        if (!rootIsComplete) {
            NSURL *temporaryStateDirectory = [stateDirectory.URLByDeletingLastPathComponent
                URLByAppendingPathComponent:[stateDirectory.lastPathComponent stringByAppendingString:@".importing"]
                                 isDirectory:YES];
            [fileManager removeItemAtURL:temporaryStateDirectory error:nil];
            if (progress != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{ progress(0, @"正在导入 Alpine rootfs…"); });
            }
            struct fakefsify_error importError = {0};
            struct progress importProgress = {
                .cookie = progress == nil ? NULL : (__bridge void *)progress,
                .callback = progress == nil ? NULL : OmniISHRootImportProgress,
            };
            BOOL imported = fakefs_import(archiveURL.fileSystemRepresentation,
                                          temporaryStateDirectory.fileSystemRepresentation,
                                          &importError,
                                          importProgress);
            if (!imported) {
                NSString *detail = importError.message == NULL ? @"Unknown import error" : [NSString stringWithUTF8String:importError.message];
                free(importError.message);
                [fileManager removeItemAtURL:temporaryStateDirectory error:nil];
                OmniISHPreparing = NO;
                NSError *error = OmniISHMakeError(OmniISHRuntimeErrorRootFileSystemImportFailed,
                                                  [NSString stringWithFormat:@"Unable to import Alpine: %@", detail]);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
                return;
            }

            NSURL *temporaryMetadataURL = [temporaryStateDirectory URLByAppendingPathComponent:@"meta.db"];
            NSURL *temporaryDataURL = [temporaryStateDirectory URLByAppendingPathComponent:@"data" isDirectory:YES];
            if (![fileManager fileExistsAtPath:temporaryMetadataURL.path] ||
                ![fileManager fileExistsAtPath:temporaryDataURL.path]) {
                [fileManager removeItemAtURL:temporaryStateDirectory error:nil];
                OmniISHPreparing = NO;
                NSError *error = OmniISHMakeError(OmniISHRuntimeErrorRootFileSystemImportFailed,
                                                  @"The imported Alpine root filesystem is incomplete.");
                dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
                return;
            }

            NSURL *temporaryMarkerURL = [temporaryStateDirectory URLByAppendingPathComponent:OmniISHRootCompletionMarkerName];
            NSString *markerContents = [expectedSHA256 stringByAppendingString:@"\n"];
            fileError = nil;
            if (![markerContents writeToURL:temporaryMarkerURL
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:&fileError]) {
                [fileManager removeItemAtURL:temporaryStateDirectory error:nil];
                OmniISHPreparing = NO;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(fileError); });
                return;
            }

            [fileManager removeItemAtURL:stateDirectory error:nil];
            fileError = nil;
            if (![fileManager moveItemAtURL:temporaryStateDirectory toURL:stateDirectory error:&fileError]) {
                [fileManager removeItemAtURL:temporaryStateDirectory error:nil];
                OmniISHPreparing = NO;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(fileError); });
                return;
            }

            metadataURL = [stateDirectory URLByAppendingPathComponent:@"meta.db"];
            dataURL = [stateDirectory URLByAppendingPathComponent:@"data" isDirectory:YES];
        }

        [fileManager createDirectoryAtURL:workspaceDirectory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&fileError];
        if (fileError != nil) {
            OmniISHPreparing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(fileError); });
            return;
        }

        OmniISHCoreBootStarted = YES;
        int bootError = mount_root(&fakefs, dataURL.fileSystemRepresentation);
        if (bootError >= 0) {
            char canonicalRoot[PATH_MAX];
            if (realpath(dataURL.fileSystemRepresentation, canonicalRoot) != NULL) {
                fakefs_set_rootfs_data_path(canonicalRoot);
            }
            bootError = become_first_process();
        }
        if (bootError < 0) {
            OmniISHCoreBootFailed = YES;
            OmniISHPreparing = NO;
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorBootFailed,
                                              [NSString stringWithFormat:@"iSH boot failed (%d).", bootError]);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }

        generic_mkdirat(AT_PWD, "/dev", 0755);
        generic_mkdirat(AT_PWD, "/dev/pts", 0755);
        generic_mkdirat(AT_PWD, "/proc", 0555);
        generic_mkdirat(AT_PWD, "/tmp", 01777);
        generic_mknodat(AT_PWD,
                        "/dev/tty",
                        S_IFCHR | 0666,
                        dev_make(TTY_ALTERNATE_MAJOR, DEV_TTY_MINOR));
        generic_mknodat(AT_PWD,
                        "/dev/ptmx",
                        S_IFCHR | 0666,
                        dev_make(TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR));
        generic_mknodat(AT_PWD, "/dev/null", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
        generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
        generic_mknodat(AT_PWD, "/dev/full", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_FULL_MINOR));
        generic_mknodat(AT_PWD, "/dev/random", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
        generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
        int procMountError = do_mount(&procfs, "proc", "/proc", "", 0);
        int devptsMountError = do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);
        if (procMountError < 0 || devptsMountError < 0) {
            OmniISHCoreBootFailed = YES;
            OmniISHPreparing = NO;
            NSError *error = OmniISHMakeError(
                OmniISHRuntimeErrorBootFailed,
                [NSString stringWithFormat:@"Unable to mount Alpine virtual filesystems (proc=%d, devpts=%d). Restart the app.",
                                           procMountError,
                                           devptsMountError]
            );
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }
        OmniISHConfigureDNS();

        int bindError = fakefs_bind_mount(OmniISHGuestWorkspacePath.UTF8String,
                                          workspaceDirectory.fileSystemRepresentation,
                                          false);
        if (bindError < 0) {
            OmniISHCoreBootFailed = YES;
            OmniISHPreparing = NO;
            NSError *error = OmniISHMakeError(OmniISHRuntimeErrorBootFailed,
                                              [NSString stringWithFormat:@"Unable to mount /workspace (%d).", bindError]);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }

        NSString *socketPrefix = [NSTemporaryDirectory() stringByAppendingPathComponent:@"omnibot-ishsock"];
        sock_tmp_prefix = strdup(socketPrefix.UTF8String);
        exit_hook = OmniISHProcessExitHook;
        OmniISHReady = YES;
        OmniISHPreparing = NO;

        if (progress != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(1, @"Alpine 已就绪"); });
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

+ (NSUUID *)executeCommand:(NSString *)command
           workingDirectory:(NSString *)workingDirectory
                 environment:(NSDictionary<NSString *,NSString *> *)environment
                     timeout:(NSTimeInterval)timeout
                 lineHandler:(OmniISHLineHandler)lineHandler
                  completion:(OmniISHCommandCompletion)completion {
    if (!OmniISHReady) {
        NSUUID *identifier = NSUUID.UUID;
        OmniISHCommandResult *result = [[OmniISHCommandResult alloc] init];
        result.exitCode = -1;
        result.processIdentifier = -1;
        result.standardOutput = @"";
        result.standardError = @"";
        result.error = OmniISHMakeError(OmniISHRuntimeErrorNotReady, @"Alpine is not ready.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        return identifier;
    }

    NSMutableDictionary<NSString *, NSString *> *effectiveEnvironment =
        [environment mutableCopy] ?: [NSMutableDictionary dictionary];
    effectiveEnvironment[@"WORKSPACE"] = OmniISHGuestWorkspacePath;
    return [ISHShellExecutor executeCommand:command
                           workingDirectory:workingDirectory
                                 environment:effectiveEnvironment
                                     timeout:timeout
                                lineCallback:lineHandler
                                  completion:^(ISHShellExecutionResult *shellResult) {
        OmniISHCommandResult *result = [[OmniISHCommandResult alloc] init];
        result.processIdentifier = shellResult.pid;
        result.exitCode = shellResult.exitCode;
        result.standardOutput = shellResult.output;
        result.standardError = shellResult.errorOutput;
        result.duration = shellResult.duration;
        if (shellResult.error != ISHShellExecutorErrorNone) {
            OmniISHRuntimeError errorCode = OmniISHRuntimeErrorExecutionFailed;
            switch (shellResult.error) {
                case ISHShellExecutorErrorProcessCreationFailed:
                    errorCode = OmniISHRuntimeErrorProcessCreationFailed;
                    break;
                case ISHShellExecutorErrorTimeout:
                    errorCode = OmniISHRuntimeErrorTimedOut;
                    break;
                case ISHShellExecutorErrorCancelled:
                    errorCode = OmniISHRuntimeErrorCancelled;
                    break;
                case ISHShellExecutorErrorNone:
                case ISHShellExecutorErrorExecFailed:
                case ISHShellExecutorErrorCleanupFailed:
                    break;
            }
            result.error = OmniISHMakeError(
                errorCode,
                shellResult.failureDescription ?: @"The Alpine command failed."
            );
        }
        completion(result);
    }];
}

+ (void)cancelExecution:(NSUUID *)executionIdentifier {
    [ISHShellExecutor cancelExecution:executionIdentifier];
}

+ (NSUUID *)startInteractiveTerminalWithWorkingDirectory:(NSString *)workingDirectory
                                              environment:(NSDictionary<NSString *,NSString *> *)environment
                                                  columns:(int)columns
                                                     rows:(int)rows
                                            outputHandler:(OmniISHTerminalOutputHandler)outputHandler
                                           startedHandler:(OmniISHTerminalStartedHandler)startedHandler
                                              exitHandler:(OmniISHTerminalExitHandler)exitHandler {
    NSUUID *identifier = NSUUID.UUID;
    OmniISHInteractiveTerminalContext *context = [[OmniISHInteractiveTerminalContext alloc]
        initWithIdentifier:identifier
        outputHandler:outputHandler
        startedHandler:startedHandler
        exitHandler:exitHandler];

    dispatch_async(OmniISHRuntimeQueue, ^{
        if (!OmniISHReady) {
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorNotReady, @"Alpine is not ready.")
            );
            return;
        }
        if (columns <= 0 || rows <= 0 || columns > 1000 || rows > 1000) {
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                 @"The interactive terminal size must be between 1 and 1000 columns/rows.")
            );
            return;
        }

        NSArray<NSString *> *arguments = @[@"/bin/sh", @"-l"];
        NSError *encodingError = nil;
        NSData *argumentData = OmniISHArgumentData(arguments, &encodingError);
        NSDictionary<NSString *, NSString *> *defaults = @{
            @"TERM": @"xterm-256color",
            @"COLORTERM": @"truecolor",
            @"HOME": @"/root",
            @"SHELL": @"/bin/sh",
            @"PATH": @"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            @"PYTHONMALLOC": @"malloc",
            @"WORKSPACE": OmniISHGuestWorkspacePath,
        };
        NSMutableDictionary<NSString *, NSString *> *mergedEnvironment = [defaults mutableCopy];
        [mergedEnvironment addEntriesFromDictionary:environment ?: @{}];
        NSData *environmentData = argumentData == nil
            ? nil
            : OmniISHEnvironmentData(mergedEnvironment, &encodingError);
        if (argumentData == nil || environmentData == nil) {
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                encodingError ?: OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                                   @"Unable to encode the interactive terminal environment.")
            );
            return;
        }

        struct task *savedCurrent = current;
        if (savedCurrent == NULL) {
            savedCurrent = pid_get_task(1);
            current = savedCurrent;
        }
        if (savedCurrent == NULL) {
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorProcessCreationFailed,
                                 @"The Alpine init process is unavailable.")
            );
            return;
        }

        int executionError = become_new_init_child();
        if (executionError < 0) {
            current = savedCurrent;
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorProcessCreationFailed,
                                 [NSString stringWithFormat:@"Unable to create an interactive guest process (%d).",
                                                            executionError])
            );
            return;
        }

        struct task *guestTask = current;
        context.guestExecutionContext = OmniISHExecutionContextFromIdentifier(identifier);
        guestTask->group->fs_context = context.guestExecutionContext;

        struct tty *terminal = NULL;
#if TARGET_OS_IOS
        Terminal *upstreamTerminal = [Terminal createPseudoTerminal:&terminal];
        if (upstreamTerminal == nil) {
#else
        terminal = pty_open_fake(&OmniISHInteractiveTerminalDriver);
        if (IS_ERR(terminal)) {
#endif
            executionError = (int)PTR_ERR(terminal);
            current = savedCurrent;
            OmniISHDestroyUnstartedGuestTask(guestTask);
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorProcessCreationFailed,
                                 [NSString stringWithFormat:@"Unable to create an interactive PTY (%d).",
                                                            executionError])
            );
            return;
        }
#if TARGET_OS_IOS
        [context attachTerminal:terminal upstreamTerminal:upstreamTerminal];
#else
        [context attachTerminal:terminal];
#endif
        [context resizeToColumns:columns rows:rows];

        NSString *stdioPath = [NSString stringWithFormat:@"/dev/pts/%d", terminal->num];
        executionError = create_stdio(stdioPath.fileSystemRepresentation,
                                      TTY_PSEUDO_SLAVE_MAJOR,
                                      terminal->num);
        if (executionError >= 0) {
            executionError = OmniISHChangeGuestWorkingDirectory(workingDirectory);
        }
        if (executionError >= 0) {
            executionError = do_execve("/bin/sh",
                                       (int)arguments.count,
                                       (char *)argumentData.bytes,
                                       (char *)environmentData.bytes);
        }
        if (executionError < 0) {
            current = savedCurrent;
            OmniISHDestroyUnstartedGuestTask(guestTask);
            OmniISHNotifyInteractiveTerminalStartFailure(
                context,
                OmniISHMakeError(OmniISHRuntimeErrorExecutionFailed,
                                 [NSString stringWithFormat:@"Unable to start the interactive Alpine shell (%d).",
                                                            executionError])
            );
            return;
        }

        context.guestProcessIdentifier = guestTask->pid;
        OmniISHInteractiveTerminals[identifier] = context;
        OmniISHInteractiveTerminalIdentifiersByPID[@(guestTask->pid)] = identifier;

        sigset_t signalSet;
        sigset_t previousSignalSet;
        sigemptyset(&signalSet);
        sigaddset(&signalSet, SIGUSR1);
        int signalMaskError = pthread_sigmask(SIG_UNBLOCK, &signalSet, &previousSignalSet);
        task_start(guestTask);
        if (signalMaskError == 0) {
            pthread_sigmask(SIG_SETMASK, &previousSignalSet, NULL);
        }
        current = savedCurrent;
        [context notifyStarted];
    });
    return identifier;
}

+ (void)sendInput:(NSData *)input toInteractiveTerminal:(NSUUID *)terminalIdentifier {
    NSData *inputCopy = [input copy];
    dispatch_async(OmniISHRuntimeQueue, ^{
        OmniISHInteractiveTerminalContext *context = OmniISHInteractiveTerminals[terminalIdentifier];
        if (context == nil || context.completed || context.processExited) {
            return;
        }
        [context enqueueInputData:inputCopy];
    });
}

+ (void)resizeInteractiveTerminal:(NSUUID *)terminalIdentifier
                           columns:(int)columns
                              rows:(int)rows {
    if (columns <= 0 || rows <= 0 || columns > 1000 || rows > 1000) {
        return;
    }
    dispatch_async(OmniISHRuntimeQueue, ^{
        OmniISHInteractiveTerminalContext *context = OmniISHInteractiveTerminals[terminalIdentifier];
        if (context == nil || context.completed || context.processExited) {
            return;
        }
        [context resizeToColumns:columns rows:rows];
    });
}

+ (void)stopInteractiveTerminal:(NSUUID *)terminalIdentifier {
    dispatch_async(OmniISHRuntimeQueue, ^{
        OmniISHInteractiveTerminalContext *context = OmniISHInteractiveTerminals[terminalIdentifier];
        if (context == nil || context.completed || context.processExited) {
            return;
        }
        OmniISHRequestInteractiveTerminalStop(
            context,
            OmniISHMakeError(OmniISHRuntimeErrorCancelled, @"The interactive terminal was stopped.")
        );
    });
}

#if TARGET_OS_IOS
+ (UIView *)viewForInteractiveTerminal:(NSUUID *)terminalIdentifier {
    NSAssert(NSThread.isMainThread, @"The iSH terminal view must be requested on the main thread.");

    __block OmniISHInteractiveTerminalContext *context = nil;
    if (dispatch_get_specific(&OmniISHRuntimeQueueSpecificKey) != NULL) {
        context = OmniISHInteractiveTerminals[terminalIdentifier];
    } else {
        dispatch_sync(OmniISHRuntimeQueue, ^{
            context = OmniISHInteractiveTerminals[terminalIdentifier];
        });
    }
    if (context == nil || context.completed || context.processExited) {
        return nil;
    }
    return [context makeUpstreamTerminalView];
}

+ (void)setControlModifier:(BOOL)controlModifier
          alternateModifier:(BOOL)alternateModifier
      forInteractiveTerminal:(NSUUID *)terminalIdentifier {
    __block OmniISHInteractiveTerminalContext *context = nil;
    if (dispatch_get_specific(&OmniISHRuntimeQueueSpecificKey) != NULL) {
        context = OmniISHInteractiveTerminals[terminalIdentifier];
    } else {
        dispatch_sync(OmniISHRuntimeQueue, ^{
            context = OmniISHInteractiveTerminals[terminalIdentifier];
        });
    }
    if (context == nil || context.completed || context.processExited) {
        return;
    }

    void (^updateModifiers)(void) = ^{
        TerminalView *terminalView = (TerminalView *)[context makeUpstreamTerminalView];
        terminalView.persistentControlModifier = controlModifier;
        terminalView.persistentAlternateModifier = alternateModifier;
    };
    if (NSThread.isMainThread) {
        updateModifiers();
    } else {
        dispatch_async(dispatch_get_main_queue(), updateModifiers);
    }
}

+ (void)sendInputKey:(OmniISHTerminalInputKey)key
    toInteractiveTerminal:(NSUUID *)terminalIdentifier {
    __block OmniISHInteractiveTerminalContext *context = nil;
    if (dispatch_get_specific(&OmniISHRuntimeQueueSpecificKey) != NULL) {
        context = OmniISHInteractiveTerminals[terminalIdentifier];
    } else {
        dispatch_sync(OmniISHRuntimeQueue, ^{
            context = OmniISHInteractiveTerminals[terminalIdentifier];
        });
    }
    if (context == nil || context.completed || context.processExited) {
        return;
    }

    void (^sendKey)(void) = ^{
        TerminalView *terminalView = (TerminalView *)[context makeUpstreamTerminalView];
        [terminalView sendInputKey:(TerminalInputKey)key];
    };
    if (NSThread.isMainThread) {
        sendKey();
    } else {
        dispatch_async(dispatch_get_main_queue(), sendKey);
    }
}

+ (void)sendText:(NSString *)text
    toInteractiveTerminal:(NSUUID *)terminalIdentifier {
    __block OmniISHInteractiveTerminalContext *context = nil;
    if (dispatch_get_specific(&OmniISHRuntimeQueueSpecificKey) != NULL) {
        context = OmniISHInteractiveTerminals[terminalIdentifier];
    } else {
        dispatch_sync(OmniISHRuntimeQueue, ^{
            context = OmniISHInteractiveTerminals[terminalIdentifier];
        });
    }
    if (context == nil || context.completed || context.processExited || text.length == 0) {
        return;
    }

    void (^sendText)(void) = ^{
        TerminalView *terminalView = (TerminalView *)[context makeUpstreamTerminalView];
        [terminalView insertText:text];
    };
    if (NSThread.isMainThread) {
        sendText();
    } else {
        dispatch_async(dispatch_get_main_queue(), sendText);
    }
}
#endif

#if DEBUG
+ (NSUInteger)debugGuestProcessCountForExecution:(NSUUID *)executionIdentifier {
    return [ISHShellExecutor debugGuestProcessCountForExecution:executionIdentifier];
}

#endif

+ (void)handleProcessExitWithIdentifier:(int)processIdentifier
                                  status:(int)status
                        executionContext:(uint64_t)executionContext {
    if ([ISHShellExecutor handleProcessExitWithPID:processIdentifier
                                            status:status
                                  executionContext:executionContext]) {
        return;
    }

    NSUUID *terminalIdentifier = OmniISHInteractiveTerminalIdentifiersByPID[@(processIdentifier)];
    OmniISHInteractiveTerminalContext *terminalContext = terminalIdentifier == nil
        ? nil
        : OmniISHInteractiveTerminals[terminalIdentifier];
    if (terminalContext != nil && terminalContext.guestExecutionContext == executionContext) {
        [self handleInteractiveTerminalExitWithIdentifier:processIdentifier
                                                    status:status
                                          executionContext:executionContext];
        return;
    }

    OmniISHReapGuestProcess(processIdentifier);
}

+ (void)handleInteractiveTerminalExitWithIdentifier:(int)processIdentifier
                                              status:(int)status
                                    executionContext:(uint64_t)executionContext {
    NSUUID *identifier = OmniISHInteractiveTerminalIdentifiersByPID[@(processIdentifier)];
    OmniISHInteractiveTerminalContext *context = identifier == nil
        ? nil
        : OmniISHInteractiveTerminals[identifier];
    if (context == nil) {
        OmniISHReapGuestProcess(processIdentifier);
        return;
    }
    if (context.completed || context.guestExecutionContext != executionContext) {
        return;
    }
    context.processExited = YES;
    context.waitStatus = status;
    [OmniISHInteractiveTerminalIdentifiersByPID removeObjectForKey:@(processIdentifier)];
    OmniISHStartInteractiveTerminalDrain(context);
}

@end
