#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN
/// CloudKit raises an Objective-C exception for an unsigned/misconfigured app.
/// Keep that exception out of Swift and report the unavailable state instead.
CKContainer * _Nullable OmniCloudKitContainerWithIdentifier(NSString *identifier);
NS_ASSUME_NONNULL_END
