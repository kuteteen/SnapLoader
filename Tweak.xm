#import <dlfcn.h>
#import <substrate.h>

@interface SBApplicationInfo : NSObject
- (NSString *)bundleIdentifier;
@end

#define dylibDir @"/Library/MobileSubstrate/DynamicLibraries"

// Basically simject
NSMutableArray *injectbookGenerateDylibList() {
	NSError *e = nil;
	NSArray *dylibDirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dylibDir error:&e];
	if (e) {
		return nil;
	}
	// We're only interested in the plist files
	NSArray *plists = [dylibDirContents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", @"plist"]];
	// Create an empty mutable array that will contain a list of dylib paths to be injected into the target process
	NSMutableArray *dylibsToInject = [NSMutableArray array];
	// Loop through the list of plists
	for (NSString *plist in plists) {
		// Don't inject injectbook itself
		if ([plist isEqualToString:@"Injectbook.plist"]) {
			continue;
		}
		// We'll want to deal with absolute paths, so append the filename to dylibDir
		NSString *plistPath = [dylibDir stringByAppendingPathComponent:plist];
		NSString *dylibPath = [[plistPath stringByDeletingPathExtension] stringByAppendingString:@".dylib"];
		// Skip missing dylibs
		if (![[NSFileManager defaultManager] fileExistsAtPath:dylibPath])
			continue;
		NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:plistPath];
		// This boolean indicates whether or not the dylib has already been injected
		BOOL isInjected = NO;
		// If supported iOS versions are specified within the plist, we check those first
		NSArray *supportedVersions = filter[@"CoreFoundationVersion"];
		if (supportedVersions) {
			if (supportedVersions.count != 1 && supportedVersions.count != 2) {
				continue; // Supported versions are in the wrong format, we should skip
			}
			if (supportedVersions.count == 1 && [supportedVersions[0] doubleValue] > kCFCoreFoundationVersionNumber) {
				continue; // Doesn't meet lower bound
			}
			if (supportedVersions.count == 2 && ([supportedVersions[0] doubleValue] > kCFCoreFoundationVersionNumber || [supportedVersions[1] doubleValue] <= kCFCoreFoundationVersionNumber)) {
				continue; // Outside bounds
			}
		}
		// Decide whether or not to load the dylib based on the Bundles values
		for (NSString *entry in filter[@"Filter"][@"Bundles"]) {
			if (![entry isEqualToString:@"com.apple.UIKit"] && ![entry isEqualToString:@"com.toyopagroup.picaboo"] && !CFBundleGetBundleWithIdentifier((CFStringRef)entry)) {
				// If not, skip it
				continue;
			}
			[dylibsToInject addObject:dylibPath];
			isInjected = YES;
			break;
		}
		if (!isInjected) {
			// Decide whether or not to load the dylib based on the Executables values
			for (NSString *process in filter[@"Filter"][@"Executables"]) {
				if ([process isEqualToString:@"Snapchat"]) {
					[dylibsToInject addObject:dylibPath];
					isInjected = YES;
					break;
				}
			}
		}
		if (!isInjected) {
			// Decide whether or not to load the dylib based on the Classes values
			for (NSString *clazz in filter[@"Filter"][@"Classes"]) {
				// Also check if this class is loaded in this application or not
				if (!NSClassFromString(clazz)) {
					// This class couldn't be loaded, skip
					continue;
				}
				// It's fine to add this dylib at this point
				[dylibsToInject addObject:dylibPath];
				isInjected = YES;
				break;
			}
		}
	}
	return dylibsToInject;
}

NSMutableDictionary *overridedEnv(NSDictionary *orig){
    NSMutableDictionary *env = orig ? orig.mutableCopy : [NSMutableDictionary dictionary];
	env[@"DYLD_INSERT_LIBRARIES"] = @"/Library/MobileSubstrate/DynamicLibraries/Injectbook.dylib";
    return env;
}

// And some app environmentVariables hack
%group SpringBoard

%hook SBApplicationInfo

- (NSDictionary *)environmentVariables {
	return [self.bundleIdentifier isEqualToString:@"com.toyopagroup.picaboo"] ? overridedEnv(%orig) : %orig;
}

%end

%end

%ctor {
	if (IN_SPRINGBOARD) {
		%init(SpringBoard);
	} else {
		for (NSString *dylib in injectbookGenerateDylibList()) {
			dlopen([dylib UTF8String], RTLD_LAZY | RTLD_GLOBAL);
		}
	}
}
