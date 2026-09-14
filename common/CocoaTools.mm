// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#if ! __has_feature(objc_arc)
	#error "Compile this with -fobjc-arc"
#endif

#include "CocoaTools.h"
#include "Console.h"
#include "HostSys.h"
#include "WindowInfo.h"
#include <dlfcn.h>
#include <mutex>
#include <vector>
#include <TargetConditionals.h>

// AppKit is macOS only. On iOS and tvOS the parts of this file that drive
// windows, menus, the Finder and NSTask have nothing to talk to - a libretro
// core owns none of those, the frontend does - so they are compiled out and
// answer "not available". What is left is Foundation, which is the same on
// every Apple platform, and it covers the four functions the core actually
// calls: the bundle path, the non-translocated bundle path, the resource path
// and the view refresh rate.
#if TARGET_OS_OSX
	#include <Cocoa/Cocoa.h>
	#include <QuartzCore/QuartzCore.h>
#else
	#include <Foundation/Foundation.h>
#endif

// MARK: - Metal Layers

static NSString*_Nonnull NSStringFromStringView(std::string_view sv)
{
	return [[NSString alloc] initWithBytes:sv.data() length:sv.size() encoding:NSUTF8StringEncoding];
}

#if !TARGET_OS_OSX

// The frontend owns the view and the layer on iOS and tvOS; this core is handed
// a surface rather than making one. Vulkan is off there as well (MoltenVK ships
// as a dylib, which is not something either system will load beside a core), so
// nothing reaches these in practice.
bool CocoaTools::CreateMetalLayer(WindowInfo*)
{
	Console.Error("CreateMetalLayer is not available on this platform.");
	return false;
}

void CocoaTools::DestroyMetalLayer(WindowInfo*)
{
}

std::optional<float> CocoaTools::GetViewRefreshRate(const WindowInfo&)
{
	// UIScreen could answer this, but the view belongs to the frontend and
	// asking about a view we were handed is not the same question. The caller
	// treats an empty answer as "use the default", which is the honest one.
	return std::nullopt;
}

#else

bool CocoaTools::CreateMetalLayer(WindowInfo* wi)
{
	if (![NSThread isMainThread])
	{
		bool ret;
		dispatch_sync(dispatch_get_main_queue(), [&ret, wi]{ ret = CreateMetalLayer(wi); });
		return ret;
	}

	CAMetalLayer* layer = [CAMetalLayer layer];
	if (!layer)
	{
		Console.Error("Failed to create Metal layer.");
		return false;
	}

	NSView* view = (__bridge NSView*)wi->window_handle;
	[view setWantsLayer:YES];
	[view setLayer:layer];
	[layer setContentsScale:[[[view window] screen] backingScaleFactor]];
	// Store the layer pointer, that way MoltenVK doesn't call [NSView layer] outside the main thread.
	wi->surface_handle = (__bridge_retained void*)layer;
	return true;
}

void CocoaTools::DestroyMetalLayer(WindowInfo* wi)
{
	if (![NSThread isMainThread])
	{
		dispatch_sync_f(dispatch_get_main_queue(), wi, [](void* ctx){ DestroyMetalLayer(static_cast<WindowInfo*>(ctx)); });
		return;
	}

	NSView* view = (__bridge NSView*)wi->window_handle;
	CAMetalLayer* layer = (__bridge_transfer CAMetalLayer*)wi->surface_handle;
	if (!layer)
		return;
	wi->surface_handle = nullptr;
	[view setLayer:nil];
	[view setWantsLayer:NO];
}

std::optional<float> CocoaTools::GetViewRefreshRate(const WindowInfo& wi)
{
	if (![NSThread isMainThread])
	{
		std::optional<float> ret;
		dispatch_sync(dispatch_get_main_queue(), [&ret, wi]{ ret = GetViewRefreshRate(wi); });
		return ret;
	}

	std::optional<float> ret;
	NSView* const view = (__bridge NSView*)wi.window_handle;
	const u32 did = [[[[[view window] screen] deviceDescription] valueForKey:@"NSScreenNumber"] unsignedIntValue];
	if (CGDisplayModeRef mode = CGDisplayCopyDisplayMode(did))
	{
		ret = CGDisplayModeGetRefreshRate(mode);
		CGDisplayModeRelease(mode);
	}
	
	return ret;
}

#endif // TARGET_OS_OSX

// MARK: - Help menu

void CocoaTools::MarkHelpMenu(void* menu)
{
#if TARGET_OS_OSX
	[NSApp setHelpMenu:(__bridge NSMenu*)menu];
#else
	(void)menu; // no menu bar to mark
#endif
}

// MARK: - Sound playback

bool Common::PlaySoundAsync(const char* path)
{
#if TARGET_OS_OSX
	NSString* nspath = [[NSString alloc] initWithUTF8String:path];
	NSSound* sound = [[NSSound alloc] initWithContentsOfFile:nspath byReference:YES];
	return [sound play];
#else
	// NSSound is AppKit. AVFoundation could do it, but nothing in a core plays
	// a system sound - this exists for the desktop UI.
	(void)path;
	return false;
#endif
}

// MARK: - Updater

std::optional<std::string> CocoaTools::GetBundlePath()
{
  std::optional<std::string> ret;
  @autoreleasepool {
    NSURL* url = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    if (url)
      ret = std::string([url fileSystemRepresentation]);
  }
  return ret;
}

std::optional<std::string> CocoaTools::GetNonTranslocatedBundlePath()
{
	// See https://objective-see.com/blog/blog_0x15.html

	NSURL* url = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
	if (!url)
		return std::nullopt;

#if TARGET_OS_OSX
	// Translocation is Gatekeeper's doing and exists only on macOS; elsewhere
	// the bundle path is already the real one.
	if (void* handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY))
	{
		auto IsTranslocatedURL = reinterpret_cast<Boolean(*)(CFURLRef path, bool* isTranslocated, CFErrorRef*__nullable error)>(dlsym(handle, "SecTranslocateIsTranslocatedURL"));
		auto CreateOriginalPathForURL = reinterpret_cast<CFURLRef __nullable(*)(CFURLRef translocatedPath, CFErrorRef*__nullable error)>(dlsym(handle, "SecTranslocateCreateOriginalPathForURL"));
		bool is_translocated = false;
		if (IsTranslocatedURL)
			IsTranslocatedURL((__bridge CFURLRef)url, &is_translocated, nullptr);
		if (is_translocated)
		{
			if (CFURLRef actual = CreateOriginalPathForURL((__bridge CFURLRef)url, nullptr))
				url = (__bridge_transfer NSURL*)actual;
		}
		dlclose(handle);
	}
#endif

	return std::string([url fileSystemRepresentation]);
}

std::optional<std::string> CocoaTools::MoveToTrash(std::string_view file)
{
	NSURL* url = [NSURL fileURLWithPath:NSStringFromStringView(file)];
	NSURL* new_url;
	if (![[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:&new_url error:nil])
		return std::nullopt;
	return std::string([new_url fileSystemRepresentation]);
}

bool CocoaTools::DelayedLaunch(std::string_view file)
{
#if !TARGET_OS_OSX
	// NSTask, /bin/sh and `open` are all desktop. Nothing relaunches an app
	// here anyway; this is the updater's path.
	(void)file;
	return false;
#else
	@autoreleasepool {
		NSTask* task = [NSTask new];
		[task setExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]];
		[task setEnvironment:@{
			@"WAITPID": [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
			@"LAUNCHAPP": NSStringFromStringView(file),
		}];
		[task setArguments:@[@"-c", @"while /bin/ps -p $WAITPID > /dev/null; do /bin/sleep 0.1; done; exec /usr/bin/open \"$LAUNCHAPP\";"]];
		return [task launchAndReturnError:nil];
	}
#endif
}

// MARK: - Directory Services

bool CocoaTools::ShowInFinder(std::string_view file)
{
#if TARGET_OS_OSX
	return [[NSWorkspace sharedWorkspace] selectFile:NSStringFromStringView(file)
	                        inFileViewerRootedAtPath:@""];
#else
	// There is no Finder to open.
	(void)file;
	return false;
#endif
}

std::optional<std::string> CocoaTools::GetResourcePath()
{ @autoreleasepool {
	if (NSBundle* bundle = [NSBundle mainBundle])
	{
		NSString* rsrc = [bundle resourcePath];
		NSString* root = [bundle bundlePath];
		if ([rsrc isEqualToString:root])
			rsrc = [rsrc stringByAppendingString:@"/resources"];
		return [rsrc UTF8String];
	}
	return std::nullopt;
}}

// MARK: - GSRunner

#if !TARGET_OS_OSX

// The GSRunner's own window and event loop. Desktop-only by construction: a
// core does not create windows, and there is no AppKit here to create one with.
void* CocoaTools::CreateWindow(std::string_view, u32, u32) { return nullptr; }
void CocoaTools::DestroyWindow(void*) {}

void CocoaTools::GetWindowInfoFromWindow(WindowInfo* wi, void*)
{
	wi->type = WindowInfo::Type::Surfaceless;
}

void CocoaTools::RunCocoaEventLoop(bool) {}
void CocoaTools::StopMainThreadEventLoop() {}

#else

void* CocoaTools::CreateWindow(std::string_view title, u32 width, u32 height)
{
	if (!NSApp)
	{
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp finishLaunching];
	}
	constexpr NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	NSScreen* mainScreen = [NSScreen mainScreen];
	// Center the window on the screen, because why not
	NSRect screenFrame = [mainScreen frame];
	NSRect viewFrame = screenFrame;
	viewFrame.size = NSMakeSize(width, height);
	viewFrame.origin.x += (screenFrame.size.width - viewFrame.size.width) / 2;
	viewFrame.origin.y += (screenFrame.size.height - viewFrame.size.height) / 2;
	NSWindow* window = [[NSWindow alloc]
		initWithContentRect:viewFrame
		          styleMask:style
		            backing:NSBackingStoreBuffered
		              defer:NO];
	[window setTitle:NSStringFromStringView(title)];
	[window makeKeyAndOrderFront:window];
	return (__bridge_retained void*)window;
}

void CocoaTools::DestroyWindow(void* window)
{
	(void)(__bridge_transfer NSWindow*)window;
}

void CocoaTools::GetWindowInfoFromWindow(WindowInfo* wi, void* cf_window)
{
	if (cf_window)
	{
		NSWindow* window = (__bridge NSWindow*)cf_window;
		float scale = [window backingScaleFactor];
		NSView* view = [window contentView];
		NSRect dims = [view frame];
		wi->type = WindowInfo::Type::MacOS;
		wi->window_handle = (__bridge void*)view;
		wi->surface_width = dims.size.width * scale;
		wi->surface_height = dims.size.height * scale;
		wi->surface_scale = scale;
	}
	else
	{
		wi->type = WindowInfo::Type::Surfaceless;
	}
}

static constexpr short STOP_EVENT_LOOP = 0x100;

void CocoaTools::RunCocoaEventLoop(bool forever)
{
	NSDate* end = forever ? [NSDate distantFuture] : [NSDate distantPast];
	[NSApplication sharedApplication]; // Ensure NSApp is initialized
	while (true)
	{ @autoreleasepool {
		NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
		                                 untilDate:end
		                                    inMode:NSDefaultRunLoopMode
		                                   dequeue:YES];
		if (!ev || ([ev type] == NSEventTypeApplicationDefined && [ev subtype] == STOP_EVENT_LOOP))
			break;
		[NSApp sendEvent:ev];
	}}
}

void CocoaTools::StopMainThreadEventLoop()
{ @autoreleasepool {
	NSEvent* ev = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
	                                 location:{}
	                            modifierFlags:0
	                                timestamp:0
	                             windowNumber:0
	                                  context:nil
	                                  subtype:STOP_EVENT_LOOP
	                                    data1:0
	                                    data2:0];
	[NSApp postEvent:ev atStart:NO];
}}

#endif // TARGET_OS_OSX
