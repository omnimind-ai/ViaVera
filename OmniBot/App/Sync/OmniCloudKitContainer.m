#import "OmniCloudKitContainer.h"

CKContainer * _Nullable OmniCloudKitContainerWithIdentifier(NSString *identifier) {
    @try {
        return [CKContainer containerWithIdentifier:identifier];
    } @catch (NSException *exception) {
        return nil;
    }
}
