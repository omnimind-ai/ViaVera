#import <Foundation/Foundation.h>
#include <TargetConditionals.h>

#if TARGET_OS_IOS
@class UIView;
#endif

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const OmniISHRuntimeErrorDomain;

typedef NS_ERROR_ENUM(OmniISHRuntimeErrorDomain, OmniISHRuntimeError) {
    OmniISHRuntimeErrorNotReady = 1,
    OmniISHRuntimeErrorRootFileSystemMissing = 2,
    OmniISHRuntimeErrorRootFileSystemImportFailed = 3,
    OmniISHRuntimeErrorBootFailed = 4,
    OmniISHRuntimeErrorProcessCreationFailed = 5,
    OmniISHRuntimeErrorExecutionFailed = 6,
    OmniISHRuntimeErrorTimedOut = 7,
    OmniISHRuntimeErrorCancelled = 8,
};

@interface OmniISHCommandResult : NSObject

@property(nonatomic, readonly) int exitCode;
@property(nonatomic, readonly) int processIdentifier;
@property(nonatomic, readonly, copy) NSString *standardOutput;
@property(nonatomic, readonly, copy) NSString *standardError;
@property(nonatomic, readonly) NSTimeInterval duration;
@property(nonatomic, readonly, nullable) NSError *error;

@end

typedef void (^OmniISHProgressHandler)(double fraction, NSString *message);
typedef void (^OmniISHPreparationCompletion)(NSError *_Nullable error);
typedef void (^OmniISHLineHandler)(NSString *line, BOOL isStandardError);
typedef void (^OmniISHCommandCompletion)(OmniISHCommandResult *result);
typedef void (^OmniISHTerminalOutputAcknowledgement)(void);
typedef void (^OmniISHTerminalOutputHandler)(
    NSData *data,
    OmniISHTerminalOutputAcknowledgement acknowledge
);
typedef void (^OmniISHTerminalStartedHandler)(int processIdentifier, NSError *_Nullable error);
typedef void (^OmniISHTerminalExitHandler)(int exitCode, NSError *_Nullable error);

typedef NS_ENUM(NSInteger, OmniISHTerminalInputKey) {
    OmniISHTerminalInputKeyEscape,
    OmniISHTerminalInputKeyTab,
    OmniISHTerminalInputKeySlash,
    OmniISHTerminalInputKeyDash,
    OmniISHTerminalInputKeyHome,
    OmniISHTerminalInputKeyArrowUp,
    OmniISHTerminalInputKeyEnd,
    OmniISHTerminalInputKeyPageUp,
    OmniISHTerminalInputKeyArrowLeft,
    OmniISHTerminalInputKeyArrowDown,
    OmniISHTerminalInputKeyArrowRight,
    OmniISHTerminalInputKeyPageDown,
    OmniISHTerminalInputKeyEnter,
    OmniISHTerminalInputKeyBackspace,
};

@interface OmniISHRuntime : NSObject

@property(class, nonatomic, readonly, getter=isReady) BOOL ready;
@property(class, nonatomic, readonly, copy) NSString *guestWorkspacePath;

+ (void)prepareWithRootFileSystemArchive:(NSURL *)archiveURL
                          expectedSHA256:(NSString *)expectedSHA256
                          stateDirectory:(NSURL *)stateDirectory
                      workspaceDirectory:(NSURL *)workspaceDirectory
                                progress:(nullable OmniISHProgressHandler)progress
                              completion:(OmniISHPreparationCompletion)completion;

+ (NSUUID *)executeCommand:(NSString *)command
           workingDirectory:(NSString *)workingDirectory
                 environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                     timeout:(NSTimeInterval)timeout
                 lineHandler:(nullable OmniISHLineHandler)lineHandler
                  completion:(OmniISHCommandCompletion)completion;

+ (void)cancelExecution:(NSUUID *)executionIdentifier;

+ (NSUUID *)startInteractiveTerminalWithWorkingDirectory:(NSString *)workingDirectory
                                              environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                                                  columns:(int)columns
                                                     rows:(int)rows
                                            outputHandler:(OmniISHTerminalOutputHandler)outputHandler
                                           startedHandler:(OmniISHTerminalStartedHandler)startedHandler
                                              exitHandler:(OmniISHTerminalExitHandler)exitHandler;

+ (void)sendInput:(NSData *)input
    toInteractiveTerminal:(NSUUID *)terminalIdentifier;

+ (void)resizeInteractiveTerminal:(NSUUID *)terminalIdentifier
                           columns:(int)columns
                              rows:(int)rows;

+ (void)stopInteractiveTerminal:(NSUUID *)terminalIdentifier;

#if TARGET_OS_IOS
+ (nullable UIView *)viewForInteractiveTerminal:(NSUUID *)terminalIdentifier;

+ (void)setControlModifier:(BOOL)controlModifier
          alternateModifier:(BOOL)alternateModifier
      forInteractiveTerminal:(NSUUID *)terminalIdentifier;

+ (void)sendInputKey:(OmniISHTerminalInputKey)key
    toInteractiveTerminal:(NSUUID *)terminalIdentifier;

+ (void)sendText:(NSString *)text
    toInteractiveTerminal:(NSUUID *)terminalIdentifier;
#endif

#if DEBUG
+ (NSUInteger)debugGuestProcessCountForExecution:(NSUUID *)executionIdentifier;
#endif

@end

NS_ASSUME_NONNULL_END
