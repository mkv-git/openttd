/* $Id: cocoa_v.mm 26544 2014-04-29 18:41:19Z frosch $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file cocoa_v.mm Code related to the cocoa video driver(s). */

/******************************************************************************
 *                             Cocoa video driver                             *
 * Known things left to do:                                                   *
 *  Nothing at the moment.                                                    *
 ******************************************************************************/

#ifdef WITH_COCOA

#include "../../stdafx.h"
#include "../../os/macosx/macos.h"

#define Rect  OTTDRect
#define Point OTTDPoint
#import <Cocoa/Cocoa.h>
#undef Rect
#undef Point

#include "../../openttd.h"
#include "../../debug.h"
#include "../../core/geometry_type.hpp"
#include "cocoa_v.h"
#include "../../blitter/factory.hpp"
#include "../../fileio_func.h"
#include "../../gfx_func.h"
#include "../../window_func.h"
#include "../../window_gui.h"

#import <sys/param.h> /* for MAXPATHLEN */

/**
 * Important notice regarding all modifications!!!!!!!
 * There are certain limitations because the file is objective C++.
 * gdb has limitations.
 * C++ and objective C code can't be joined in all cases (classes stuff).
 * Read http://developer.apple.com/releasenotes/Cocoa/Objective-C++.html for more information.
 */


@interface OTTDMain : NSObject
@end


static NSAutoreleasePool *_ottd_autorelease_pool;
static OTTDMain *_ottd_main;
static bool _cocoa_video_started = false;
static bool _cocoa_video_dialog = false;

CocoaSubdriver *_cocoa_subdriver = NULL;

static NSString *OTTDMainLaunchGameEngine = @"ottdmain_launch_game_engine";


/**
 * The main class of the application, the application's delegate.
 */
@implementation OTTDMain
/**
 * Stop the game engine. Must be called on main thread.
 */
- (void)stopEngine
{
	[ NSApp stop:self ];

	/* Send an empty event to return from the run loop. Without that, application is stuck waiting for an event. */
	NSEvent *event = [ NSEvent otherEventWithType:NSApplicationDefined location:NSMakePoint(0, 0) modifierFlags:0 timestamp:0.0 windowNumber:0 context:nil subtype:0 data1:0 data2:0 ];
	[ NSApp postEvent:event atStart:YES ];
}

/**
 * Start the game loop.
 */
- (void)launchGameEngine: (NSNotification*) note
{
	/* Setup cursor for the current _game_mode. */
	[ _cocoa_subdriver->cocoaview resetCursorRects ];

	/* Hand off to main application code. */
	QZ_GameLoop();

	/* We are done, thank you for playing. */
	[ self performSelectorOnMainThread:@selector(stopEngine) withObject:nil waitUntilDone:FALSE ];
}

/**
 * Called when the internal event loop has just started running.
 */
- (void) applicationDidFinishLaunching: (NSNotification*) note
{
	/* Add a notification observer so we can restart the game loop later on if necessary. */
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(launchGameEngine:) name:OTTDMainLaunchGameEngine object:nil ];

	/* Start game loop. */
	[ [ NSNotificationCenter defaultCenter ] postNotificationName:OTTDMainLaunchGameEngine object:nil ];
}

/**
 * Display the in game quit confirmation dialog.
 */
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*) sender
{
	HandleExitGameRequest();

	return NSTerminateCancel; // NSTerminateLater ?
}

/**
 * Remove ourself as a notification observer.
 */
- (void)unregisterObserver
{
	[ [ NSNotificationCenter defaultCenter ] removeObserver:self ];
}
@end

/**
 * Initialize the application menu shown in top bar.
 */
static void setApplicationMenu()
{
	NSString *appName = @"OpenTTD";
	NSMenu *appleMenu = [ [ NSMenu alloc ] initWithTitle:appName ];

	/* Add menu items */
	NSString *title = [ @"About " stringByAppendingString:appName ];
	[ appleMenu addItemWithTitle:title action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@"" ];

	[ appleMenu addItem:[ NSMenuItem separatorItem ] ];

	title = [ @"Hide " stringByAppendingString:appName ];
	[ appleMenu addItemWithTitle:title action:@selector(hide:) keyEquivalent:@"h" ];

	NSMenuItem *menuItem = [ appleMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h" ];
	[ menuItem setKeyEquivalentModifierMask:(NSAlternateKeyMask | NSCommandKeyMask) ];

	[ appleMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@"" ];

	[ appleMenu addItem:[ NSMenuItem separatorItem ] ];

	title = [ @"Quit " stringByAppendingString:appName ];
	[ appleMenu addItemWithTitle:title action:@selector(terminate:) keyEquivalent:@"q" ];

	/* Put menu into the menubar */
	menuItem = [ [ NSMenuItem alloc ] initWithTitle:@"" action:nil keyEquivalent:@"" ];
	[ menuItem setSubmenu:appleMenu ];
	[ [ NSApp mainMenu ] addItem:menuItem ];

	/* Tell the application object that this is now the application menu.
	 * This interesting Objective-C construct is used because not all SDK
	 * versions define this method publicly. */
	[ NSApp performSelector:@selector(setAppleMenu:) withObject:appleMenu ];

	/* Finally give up our references to the objects */
	[ appleMenu release ];
	[ menuItem release ];
}

/**
 * Create a window menu.
 */
static void setupWindowMenu()
{
	NSMenu *windowMenu = [ [ NSMenu alloc ] initWithTitle:@"Window" ];

	/* "Minimize" item */
	[ windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m" ];

	/* Put menu into the menubar */
	NSMenuItem *menuItem = [ [ NSMenuItem alloc ] initWithTitle:@"Window" action:nil keyEquivalent:@"" ];
	[ menuItem setSubmenu:windowMenu ];
	[ [ NSApp mainMenu ] addItem:menuItem ];

	if (MacOSVersionIsAtLeast(10, 7, 0)) {
		/* The OS will change the name of this menu item automatically */
		[ windowMenu addItemWithTitle:@"Fullscreen" action:@selector(toggleFullScreen:) keyEquivalent:@"^f" ];
	}

	/* Tell the application object that this is now the window menu */
	[ NSApp setWindowsMenu:windowMenu ];

	/* Finally give up our references to the objects */
	[ windowMenu release ];
	[ menuItem release ];
}

/**
 * Startup the application.
 */
static void setupApplication()
{
	ProcessSerialNumber psn = { 0, kCurrentProcess };

	/* Ensure the application object is initialised */
	[ NSApplication sharedApplication ];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
	/* Tell the dock about us */
	if (MacOSVersionIsAtLeast(10, 3, 0)) {
		OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToForegroundApplication);
		if (returnCode != 0) DEBUG(driver, 0, "Could not change to foreground application. Error %d", (int)returnCode);
	}
#endif

	/* Become the front process, important when start from the command line. */
	OSErr err = SetFrontProcess(&psn);
	if (err != 0) DEBUG(driver, 0, "Could not bring the application to front. Error %d", (int)err);

	/* Set up the menubar */
	[ NSApp setMainMenu:[ [ NSMenu alloc ] init ] ];
	setApplicationMenu();
	setupWindowMenu();

	/* Create OTTDMain and make it the app delegate */
	_ottd_main = [ [ OTTDMain alloc ] init ];
	[ NSApp setDelegate:_ottd_main ];
}


static int CDECL ModeSorter(const OTTD_Point *p1, const OTTD_Point *p2)
{
	if (p1->x < p2->x) return -1;
	if (p1->x > p2->x) return +1;
	if (p1->y < p2->y) return -1;
	if (p1->y > p2->y) return +1;
	return 0;
}

uint QZ_ListModes(OTTD_Point *modes, uint max_modes, CGDirectDisplayID display_id, int device_depth)
{
	CFArrayRef mode_list  = CGDisplayAvailableModes(display_id);
	CFIndex    num_modes = CFArrayGetCount(mode_list);

	/* Build list of modes with the requested bpp */
	uint count = 0;
	for (CFIndex i = 0; i < num_modes && count < max_modes; i++) {
		int intvalue, bpp;
		uint16 width, height;

		CFDictionaryRef onemode = (const __CFDictionary*)CFArrayGetValueAtIndex(mode_list, i);
		CFNumberRef number = (const __CFNumber*)CFDictionaryGetValue(onemode, kCGDisplayBitsPerPixel);
		CFNumberGetValue(number, kCFNumberSInt32Type, &bpp);

		if (bpp != device_depth) continue;

		number = (const __CFNumber*)CFDictionaryGetValue(onemode, kCGDisplayWidth);
		CFNumberGetValue(number, kCFNumberSInt32Type, &intvalue);
		width = (uint16)intvalue;

		number = (const __CFNumber*)CFDictionaryGetValue(onemode, kCGDisplayHeight);
		CFNumberGetValue(number, kCFNumberSInt32Type, &intvalue);
		height = (uint16)intvalue;

		/* Check if mode is already in the list */
		bool hasMode = false;
		for (uint i = 0; i < count; i++) {
			if (modes[i].x == width &&  modes[i].y == height) {
				hasMode = true;
				break;
			}
		}

		if (hasMode) continue;

		/* Add mode to the list */
		modes[count].x = width;
		modes[count].y = height;
		count++;
	}

	/* Sort list smallest to largest */
	QSortT(modes, count, &ModeSorter);

	return count;
}

/** Small function to test if the main display can display 8 bpp in fullscreen */
bool QZ_CanDisplay8bpp()
{
	/* 8bpp modes are deprecated starting in 10.5. CoreGraphics will return them
	 * as available in the display list, but many features (e.g. palette animation)
	 * will be broken. */
	if (MacOSVersionIsAtLeast(10, 5, 0)) return false;

	OTTD_Point p;

	/* We want to know if 8 bpp is possible in fullscreen and not anything about
	 * resolutions. Because of this we want to fill a list of 1 resolution of 8 bpp
	 * on display 0 (main) and return if we found one. */
	return QZ_ListModes(&p, 1, 0, 8);
}

/**
 * Update the video modus.
 *
 * @pre _cocoa_subdriver != NULL
 */
static void QZ_UpdateVideoModes()
{
	assert(_cocoa_subdriver != NULL);

	OTTD_Point modes[32];
	uint count = _cocoa_subdriver->ListModes(modes, lengthof(modes));

	for (uint i = 0; i < count; i++) {
		_resolutions[i].width  = modes[i].x;
		_resolutions[i].height = modes[i].y;
	}

	_num_resolutions = count;
}

/**
 * Handle a change of the display area.
 */
void QZ_GameSizeChanged()
{
	if (_cocoa_subdriver == NULL) return;

	/* Tell the game that the resolution has changed */
	_screen.width = _cocoa_subdriver->GetWidth();
	_screen.height = _cocoa_subdriver->GetHeight();
	_screen.pitch = _cocoa_subdriver->GetWidth();
	_screen.dst_ptr = _cocoa_subdriver->GetPixelBuffer();
	_fullscreen = _cocoa_subdriver->IsFullscreen();

	BlitterFactory::GetCurrentBlitter()->PostResize();

	GameSizeChanged();
}

/**
 * Find a suitable cocoa window subdriver.
 *
 * @param width Width of display area.
 * @param height Height of display area.
 * @param bpp Colour depth of display area.
 * @return Pointer to window subdriver.
 */
static CocoaSubdriver *QZ_CreateWindowSubdriver(int width, int height, int bpp)
{
#if defined(ENABLE_COCOA_QUARTZ) || defined(ENABLE_COCOA_QUICKDRAW)
	CocoaSubdriver *ret;
#endif

#if defined(ENABLE_COCOA_QUARTZ) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4)
	/* The reason for the version mismatch is due to the fact that the 10.4 binary needs to work on 10.5 as well. */
	if (MacOSVersionIsAtLeast(10, 5, 0)) {
		ret = QZ_CreateWindowQuartzSubdriver(width, height, bpp);
		if (ret != NULL) return ret;
	}
#endif

#ifdef ENABLE_COCOA_QUICKDRAW
	ret = QZ_CreateWindowQuickdrawSubdriver(width, height, bpp);
	if (ret != NULL) return ret;
#endif

#if defined(ENABLE_COCOA_QUARTZ) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4)
	/*
	 * If we get here we are running 10.4 or earlier and either openttd was compiled without the QuickDraw driver
	 * or it failed to load for some reason. Fall back to Quartz if possible even though that driver is slower.
	 */
	if (MacOSVersionIsAtLeast(10, 4, 0)) {
		ret = QZ_CreateWindowQuartzSubdriver(width, height, bpp);
		if (ret != NULL) return ret;
	}
#endif

	return NULL;
}

/**
 * Find a suitable cocoa subdriver.
 *
 * @param width Width of display area.
 * @param height Height of display area.
 * @param bpp Colour depth of display area.
 * @param fullscreen Whether a fullscreen mode is requested.
 * @param fallback Whether we look for a fallback driver.
 * @return Pointer to window subdriver.
 */
static CocoaSubdriver *QZ_CreateSubdriver(int width, int height, int bpp, bool fullscreen, bool fallback)
{
	CocoaSubdriver *ret = NULL;
	/* OSX 10.7 allows to toggle fullscreen mode differently */
	if (MacOSVersionIsAtLeast(10, 7, 0)) {
		ret = QZ_CreateWindowSubdriver(width, height, bpp);
		if (ret != NULL && fullscreen) ret->ToggleFullscreen();
	}
#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_9)
	else {
		ret = fullscreen ? QZ_CreateFullscreenSubdriver(width, height, bpp) : QZ_CreateWindowSubdriver(width, height, bpp);
	}
#endif /* (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_9) */

	if (ret != NULL) return ret;
	if (!fallback) return NULL;

	/* Try again in 640x480 windowed */
	DEBUG(driver, 0, "Setting video mode failed, falling back to 640x480 windowed mode.");
	ret = QZ_CreateWindowSubdriver(640, 480, bpp);
	if (ret != NULL) return ret;

#if defined(_DEBUG) && (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_9)
	/* This Fullscreen mode crashes on OSX 10.7 */
	if (!MacOSVersionIsAtLeast(10, 7, 0)) {
		/* Try fullscreen too when in debug mode */
		DEBUG(driver, 0, "Setting video mode failed, falling back to 640x480 fullscreen mode.");
		ret = QZ_CreateFullscreenSubdriver(640, 480, bpp);
		if (ret != NULL) return ret;
	}
#endif /* defined(_DEBUG) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_9) */

	return NULL;
}


static FVideoDriver_Cocoa iFVideoDriver_Cocoa;

/**
 * Stop the cocoa video subdriver.
 */
void VideoDriver_Cocoa::Stop()
{
	if (!_cocoa_video_started) return;

	[ _ottd_main unregisterObserver ];

	delete _cocoa_subdriver;
	_cocoa_subdriver = NULL;

	[ _ottd_main release ];

	_cocoa_video_started = false;
}

/**
 * Initialize a cocoa video subdriver.
 */
const char *VideoDriver_Cocoa::Start(const char * const *parm)
{
	if (!MacOSVersionIsAtLeast(10, 3, 0)) return "The Cocoa video driver requires Mac OS X 10.3 or later.";

	if (_cocoa_video_started) return "Already started";
	_cocoa_video_started = true;

	setupApplication();

	/* Don't create a window or enter fullscreen if we're just going to show a dialog. */
	if (_cocoa_video_dialog) return NULL;

	int width  = _cur_resolution.width;
	int height = _cur_resolution.height;
	int bpp = BlitterFactory::GetCurrentBlitter()->GetScreenDepth();

	_cocoa_subdriver = QZ_CreateSubdriver(width, height, bpp, _fullscreen, true);
	if (_cocoa_subdriver == NULL) {
		Stop();
		return "Could not create subdriver";
	}

	QZ_GameSizeChanged();
	QZ_UpdateVideoModes();

	return NULL;
}

/**
 * Set dirty a rectangle managed by a cocoa video subdriver.
 *
 * @param left Left x cooordinate of the dirty rectangle.
 * @param top Uppder y coordinate of the dirty rectangle.
 * @param width Width of the dirty rectangle.
 * @param height Height of the dirty rectangle.
 */
void VideoDriver_Cocoa::MakeDirty(int left, int top, int width, int height)
{
	assert(_cocoa_subdriver != NULL);

	_cocoa_subdriver->MakeDirty(left, top, width, height);
}

/**
 * Start the main programme loop when using a cocoa video driver.
 */
void VideoDriver_Cocoa::MainLoop()
{
	/* Restart game loop if it was already running (e.g. after bootstrapping),
	 * otherwise this call is a no-op. */
	[ [ NSNotificationCenter defaultCenter ] postNotificationName:OTTDMainLaunchGameEngine object:nil ];

	/* Start the main event loop. */
	[ NSApp run ];
}

/**
 * Change the resolution when using a cocoa video driver.
 *
 * @param w New window width.
 * @param h New window height.
 * @return Whether the video driver was successfully updated.
 */
bool VideoDriver_Cocoa::ChangeResolution(int w, int h)
{
	assert(_cocoa_subdriver != NULL);

	bool ret = _cocoa_subdriver->ChangeResolution(w, h, BlitterFactory::GetCurrentBlitter()->GetScreenDepth());

	QZ_GameSizeChanged();
	QZ_UpdateVideoModes();

	return ret;
}

/**
 * Toggle between windowed and full screen mode for cocoa display driver.
 *
 * @param full_screen Whether to switch to full screen or not.
 * @return Whether the mode switch was successful.
 */
bool VideoDriver_Cocoa::ToggleFullscreen(bool full_screen)
{
	assert(_cocoa_subdriver != NULL);

	/* For 10.7 and later, we try to toggle using the quartz subdriver. */
	if (_cocoa_subdriver->ToggleFullscreen()) return true;

	bool oldfs = _cocoa_subdriver->IsFullscreen();
	if (full_screen != oldfs) {
		int width  = _cocoa_subdriver->GetWidth();
		int height = _cocoa_subdriver->GetHeight();
		int bpp    = BlitterFactory::GetCurrentBlitter()->GetScreenDepth();

		delete _cocoa_subdriver;
		_cocoa_subdriver = NULL;

		_cocoa_subdriver = QZ_CreateSubdriver(width, height, bpp, full_screen, false);
		if (_cocoa_subdriver == NULL) {
			_cocoa_subdriver = QZ_CreateSubdriver(width, height, bpp, oldfs, true);
			if (_cocoa_subdriver == NULL) error("Cocoa: Failed to create subdriver");
		}
	}

	QZ_GameSizeChanged();
	QZ_UpdateVideoModes();

	return _cocoa_subdriver->IsFullscreen() == full_screen;
}

/**
 * Callback invoked after the blitter was changed.
 *
 * @return True if no error.
 */
bool VideoDriver_Cocoa::AfterBlitterChange()
{
	return this->ChangeResolution(_screen.width, _screen.height);
}

/**
 * An edit box lost the input focus. Abort character compositing if necessary.
 */
void VideoDriver_Cocoa::EditBoxLostFocus()
{
	if (_cocoa_subdriver != NULL) {
		if ([ _cocoa_subdriver->cocoaview respondsToSelector:@selector(inputContext) ] && [ [ _cocoa_subdriver->cocoaview performSelector:@selector(inputContext) ] respondsToSelector:@selector(discardMarkedText) ]) {
			[ [ _cocoa_subdriver->cocoaview performSelector:@selector(inputContext) ] performSelector:@selector(discardMarkedText) ];
		} else {
			[ [ NSInputManager currentInputManager ] markedTextAbandoned:_cocoa_subdriver->cocoaview ];
		}
	}
	/* Clear any marked string from the current edit box. */
	HandleTextInput(NULL, true);
}

/**
 * Catch asserts prior to initialization of the videodriver.
 *
 * @param title Window title.
 * @param message Message text.
 * @param buttonLabel Button text.
 *
 * @note This is needed since sometimes assert is called before the videodriver is initialized .
 */
void CocoaDialog(const char *title, const char *message, const char *buttonLabel)
{
	_cocoa_video_dialog = true;

	bool wasstarted = _cocoa_video_started;
	if (VideoDriver::GetInstance() == NULL) {
		setupApplication(); // Setup application before showing dialog
	} else if (!_cocoa_video_started && VideoDriver::GetInstance()->Start(NULL) != NULL) {
		fprintf(stderr, "%s: %s\n", title, message);
		return;
	}

	NSRunAlertPanel([ NSString stringWithUTF8String:title ], [ NSString stringWithUTF8String:message ], [ NSString stringWithUTF8String:buttonLabel ], nil, nil);

	if (!wasstarted && VideoDriver::GetInstance() != NULL) VideoDriver::GetInstance()->Stop();

	_cocoa_video_dialog = false;
}

/** Set the application's bundle directory.
 *
 * This is needed since OS X application bundles do not have a
 * current directory and the data files are 'somewhere' in the bundle.
 */
void cocoaSetApplicationBundleDir()
{
	char tmp[MAXPATHLEN];
	CFURLRef url = CFBundleCopyResourcesDirectoryURL(CFBundleGetMainBundle());
	if (CFURLGetFileSystemRepresentation(url, true, (unsigned char*)tmp, MAXPATHLEN)) {
		AppendPathSeparator(tmp, lengthof(tmp));
		_searchpaths[SP_APPLICATION_BUNDLE_DIR] = strdup(tmp);
	} else {
		_searchpaths[SP_APPLICATION_BUNDLE_DIR] = NULL;
	}

	CFRelease(url);
}

/**
 * Setup autorelease for the application pool.
 *
 * These are called from main() to prevent a _NSAutoreleaseNoPool error when
 * exiting before the cocoa video driver has been loaded
 */
void cocoaSetupAutoreleasePool()
{
	_ottd_autorelease_pool = [ [ NSAutoreleasePool alloc ] init ];
}

/**
 * Autorelease the application pool.
 */
void cocoaReleaseAutoreleasePool()
{
	[ _ottd_autorelease_pool release ];
}


/**
 * Re-implement the system cursor in order to allow hiding and showing it nicely
 */
@implementation NSCursor (OTTD_CocoaCursor)
+ (NSCursor *) clearCocoaCursor
{
	/* RAW 16x16 transparent GIF */
	unsigned char clearGIFBytes[] = {
		0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x10, 0x00, 0x10, 0x00, 0x80, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x01, 0x00,
		0x00, 0x01, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x10, 0x00,
		0x00, 0x02, 0x0E, 0x8C, 0x8F, 0xA9, 0xCB, 0xED, 0x0F, 0xA3, 0x9C, 0xB4,
		0xDA, 0x8B, 0xB3, 0x3E, 0x05, 0x00, 0x3B};
	NSData *clearGIFData = [ NSData dataWithBytesNoCopy:&clearGIFBytes[0] length:55 freeWhenDone:NO ];
	NSImage *clearImg = [ [ NSImage alloc ] initWithData:clearGIFData ];
	return [ [ NSCursor alloc ] initWithImage:clearImg hotSpot:NSMakePoint(0.0,0.0) ];
}
@end



@implementation OTTD_CocoaWindow

- (void)setDriver:(CocoaSubdriver*)drv
{
	driver = drv;
}
/**
 * Minimize the window
 */
- (void)miniaturize:(id)sender
{
	/* make the alpha channel opaque so anim won't have holes in it */
	driver->SetPortAlphaOpaque();

	/* window is hidden now */
	driver->active = false;

	[ super miniaturize:sender ];
}

/**
 * This method fires just before the window deminaturizes from the Dock.
 * We'll save the current visible surface, let the window manager redraw any
 * UI elements, and restore the surface. This way, no expose event
 * is required, and the deminiaturize works perfectly.
 */
- (void)display
{
	driver->SetPortAlphaOpaque();

	/* save current visible surface */
	[ self cacheImageInRect:[ driver->cocoaview frame ] ];

	/* let the window manager redraw controls, border, etc */
	[ super display ];

	/* restore visible surface */
	[ self restoreCachedImage ];

	/* window is visible again */
	driver->active = true;
}
/**
 * Define the rectangle we draw our window in
 */
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag
{
	[ super setFrame:frameRect display:flag ];

	/* Don't do anything if the window is currently being created */
	if (driver->setup) return;

	if (!driver->WindowResized()) error("Cocoa: Failed to resize window.");
}
/**
 * Handle hiding of the application
 */
- (void)appDidHide:(NSNotification*)note
{
	driver->active = false;
}
/**
 * Fade-in the application and restore display plane
 */
- (void)appWillUnhide:(NSNotification*)note
{
	driver->SetPortAlphaOpaque ();
}
/**
 * Unhide and restore display plane and re-activate driver
 */
- (void)appDidUnhide:(NSNotification*)note
{
	driver->active = true;
}
/**
 * Initialize event system for the application rectangle
 */
- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
	/* Make our window subclass receive these application notifications */
	[ [ NSNotificationCenter defaultCenter ] addObserver:self
		selector:@selector(appDidHide:) name:NSApplicationDidHideNotification object:NSApp ];

	[ [ NSNotificationCenter defaultCenter ] addObserver:self
		selector:@selector(appDidUnhide:) name:NSApplicationDidUnhideNotification object:NSApp ];

	[ [ NSNotificationCenter defaultCenter ] addObserver:self
		selector:@selector(appWillUnhide:) name:NSApplicationWillUnhideNotification object:NSApp ];

	return [ super initWithContentRect:contentRect styleMask:styleMask backing:backingType defer:flag ];
}

@end



/**
 * Count the number of UTF-16 code points in a range of an UTF-8 string.
 * @param from Start of the range.
 * @param to End of the range.
 * @return Number of UTF-16 code points in the range.
 */
static NSUInteger CountUtf16Units(const char *from, const char *to)
{
	NSUInteger i = 0;

	while (from < to) {
		WChar c;
		size_t len = Utf8Decode(&c, from);
		i += len < 4 ? 1 : 2; // Watch for surrogate pairs.
		from += len;
	}

	return i;
}

/**
 * Advance an UTF-8 string by a number of equivalent UTF-16 code points.
 * @param str UTF-8 string.
 * @param count Number of UTF-16 code points to advance the string by.
 * @return Advanced string pointer.
 */
static const char *Utf8AdvanceByUtf16Units(const char *str, NSUInteger count)
{
	for (NSUInteger i = 0; i < count && *str != '\0'; ) {
		WChar c;
		size_t len = Utf8Decode(&c, str);
		i += len < 4 ? 1 : 2; // Watch for surrogates.
		str += len;
	}

	return str;
}

@implementation OTTD_CocoaView
/**
 * Initialize the driver
 */
- (void)setDriver:(CocoaSubdriver*)drv
{
	driver = drv;
}
/**
 * Define the opaqueness of the window / screen
 * @return opaqueness of window / screen
 */
- (BOOL)isOpaque
{
	return YES;
}
/**
 * Draws a rectangle on the screen.
 * It's overwritten by the individual drivers but must be defined
 */
- (void)drawRect:(NSRect)invalidRect
{
	return;
}
/**
 * Allow to handle events
 */
- (BOOL)acceptsFirstResponder
{
	return YES;
}
/**
 * Actually handle events
 */
- (BOOL)becomeFirstResponder
{
	return YES;
}
/**
 * Define the rectangle where we draw our application window
 */
- (void)setTrackingRect
{
	NSPoint loc = [ self convertPoint:[ [ self window ] mouseLocationOutsideOfEventStream ] fromView:nil ];
	BOOL inside = ([ self hitTest:loc ]==self);
	if (inside) [ [ self window ] makeFirstResponder:self ];
	trackingtag = [ self addTrackingRect:[ self visibleRect ] owner:self userData:nil assumeInside:inside ];
}
/**
 * Return responsibility for the application window to system
 */
- (void)clearTrackingRect
{
	[ self removeTrackingRect:trackingtag ];
}
/**
 * Declare responsibility for the cursor within our application rect
 */
- (void)resetCursorRects
{
	[ super resetCursorRects ];
	[ self clearTrackingRect ];
	[ self setTrackingRect ];
	[ self addCursorRect:[ self bounds ] cursor:(_game_mode == GM_BOOTSTRAP ? [ NSCursor arrowCursor ] : [ NSCursor clearCocoaCursor ]) ];
}
/**
 * Prepare for moving the application window
 */
- (void)viewWillMoveToWindow:(NSWindow *)win
{
	if (!win && [ self window ]) [ self clearTrackingRect ];
}
/**
 * Restore our responsibility for our application window after moving
 */
- (void)viewDidMoveToWindow
{
	if ([ self window ]) [ self setTrackingRect ];
}
/**
 * Make OpenTTD aware that it has control over the mouse
 */
- (void)mouseEntered:(NSEvent *)theEvent
{
	_cursor.in_window = true;
}
/**
 * Make OpenTTD aware that it has NOT control over the mouse
 */
- (void)mouseExited:(NSEvent *)theEvent
{
	if (_cocoa_subdriver != NULL) UndrawMouseCursor();
	_cursor.in_window = false;
}


/** Insert the given text at the given range. */
- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange
{
	if (!EditBoxInGlobalFocus()) return;

	NSString *s = [ aString isKindOfClass:[ NSAttributedString class ] ] ? [ aString string ] : (NSString *)aString;

	const char *insert_point = NULL;
	const char *replace_range = NULL;
	if (replacementRange.location != NSNotFound) {
		/* Calculate the part to be replaced. */
		insert_point = Utf8AdvanceByUtf16Units(_focused_window->GetFocusedText(), replacementRange.location);
		replace_range = Utf8AdvanceByUtf16Units(insert_point, replacementRange.length);
	}

	HandleTextInput(NULL, true);
	HandleTextInput([ s UTF8String ], false, NULL, insert_point, replace_range);
}

/** Insert the given text at the caret. */
- (void)insertText:(id)aString
{
	[ self insertText:aString replacementRange:NSMakeRange(NSNotFound, 0) ];
}

/** Set a new marked text and reposition the caret. */
- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange replacementRange:(NSRange)replacementRange
{
	if (!EditBoxInGlobalFocus()) return;

	NSString *s = [ aString isKindOfClass:[ NSAttributedString class ] ] ? [ aString string ] : (NSString *)aString;

	const char *utf8 = [ s UTF8String ];
	if (utf8 != NULL) {
		const char *insert_point = NULL;
		const char *replace_range = NULL;
		if (replacementRange.location != NSNotFound) {
			/* Calculate the part to be replaced. */
			NSRange marked = [ self markedRange ];
			insert_point = Utf8AdvanceByUtf16Units(_focused_window->GetFocusedText(), replacementRange.location + (marked.location != NSNotFound ? marked.location : 0u));
			replace_range = Utf8AdvanceByUtf16Units(insert_point, replacementRange.length);
		}

		/* Convert caret index into a pointer in the UTF-8 string. */
		const char *selection = Utf8AdvanceByUtf16Units(utf8, selRange.location);

		HandleTextInput(utf8, true, selection, insert_point, replace_range);
	}
}

/** Set a new marked text and reposition the caret. */
- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange
{
	[ self setMarkedText:aString selectedRange:selRange replacementRange:NSMakeRange(NSNotFound, 0) ];
}

/** Unmark the current marked text. */
- (void)unmarkText
{
	HandleTextInput(NULL, true);
}

/** Get the caret position. */
- (NSRange)selectedRange
{
	if (!EditBoxInGlobalFocus()) return NSMakeRange(NSNotFound, 0);

	NSUInteger start = CountUtf16Units(_focused_window->GetFocusedText(), _focused_window->GetCaret());
	return NSMakeRange(start, 0);
}

/** Get the currently marked range. */
- (NSRange)markedRange
{
	if (!EditBoxInGlobalFocus()) return NSMakeRange(NSNotFound, 0);

	size_t mark_len;
	const char *mark = _focused_window->GetMarkedText(&mark_len);
	if (mark != NULL) {
		NSUInteger start = CountUtf16Units(_focused_window->GetFocusedText(), mark);
		NSUInteger len = CountUtf16Units(mark, mark + mark_len);

		return NSMakeRange(start, len);
	}

	return NSMakeRange(NSNotFound, 0);
}

/** Is any text marked? */
- (BOOL)hasMarkedText
{
	if (!EditBoxInGlobalFocus()) return NO;

	size_t len;
	return _focused_window->GetMarkedText(&len) != NULL;
}

/** Get a string corresponding to the given range. */
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)theRange actualRange:(NSRangePointer)actualRange
{
	if (!EditBoxInGlobalFocus()) return nil;

	NSString *s = [ NSString stringWithUTF8String:_focused_window->GetFocusedText() ];
	NSRange valid_range = NSIntersectionRange(NSMakeRange(0, [ s length ]), theRange);

	if (actualRange != NULL) *actualRange = valid_range;
	if (valid_range.length == 0) return nil;

	return [ [ [ NSAttributedString alloc ] initWithString:[ s substringWithRange:valid_range ] ] autorelease ];
}

/** Get a string corresponding to the given range. */
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
	return [ self attributedSubstringForProposedRange:theRange actualRange:NULL ];
}

/** Get the current edit box string. */
- (NSAttributedString *)attributedString
{
	if (!EditBoxInGlobalFocus()) return [ [ [ NSAttributedString alloc ] initWithString:@"" ] autorelease ];

	return [ [ [ NSAttributedString alloc ] initWithString:[ NSString stringWithUTF8String:_focused_window->GetFocusedText() ] ] autorelease ];
}

/** Get the character that is rendered at the given point. */
- (NSUInteger)characterIndexForPoint:(NSPoint)thePoint
{
	if (!EditBoxInGlobalFocus()) return NSNotFound;

	NSPoint view_pt = [ self convertPoint:[ [ self window ] convertScreenToBase:thePoint ] fromView:nil ];

	Point pt = { (int)view_pt.x, (int)[ self frame ].size.height - (int)view_pt.y };

	const char *ch = _focused_window->GetTextCharacterAtPosition(pt);
	if (ch == NULL) return NSNotFound;

	return CountUtf16Units(_focused_window->GetFocusedText(), ch);
}

/** Get the bounding rect for the given range. */
- (NSRect)firstRectForCharacterRange:(NSRange)aRange
{
	if (!EditBoxInGlobalFocus()) return NSMakeRect(0, 0, 0, 0);

	/* Convert range to UTF-8 string pointers. */
	const char *start = Utf8AdvanceByUtf16Units(_focused_window->GetFocusedText(), aRange.location);
	const char *end = aRange.length != 0 ? Utf8AdvanceByUtf16Units(_focused_window->GetFocusedText(), aRange.location + aRange.length) : start;

	/* Get the bounding rect for the text range.*/
	Rect r = _focused_window->GetTextBoundingRect(start, end);
	NSRect view_rect = NSMakeRect(_focused_window->left + r.left, [ self frame ].size.height - _focused_window->top - r.bottom, r.right - r.left, r.bottom - r.top);

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
	if ([ [ self window ] respondsToSelector:@selector(convertRectToScreen:) ]) {
		return [ [ self window ] convertRectToScreen:[ self convertRect:view_rect toView:nil ] ];
	}
#endif

	NSRect window_rect = [ self convertRect:view_rect toView:nil ];
	NSPoint origin = [ [ self window ] convertBaseToScreen:window_rect.origin ];
	return NSMakeRect(origin.x, origin.y, window_rect.size.width, window_rect.size.height);
}

/** Get the bounding rect for the given range. */
- (NSRect)firstRectForCharacterRange:(NSRange)aRange actualRange:(NSRangePointer)actualRange
{
	return [ self firstRectForCharacterRange:aRange ];
}

/** Get all string attributes that we can process for marked text. */
- (NSArray*)validAttributesForMarkedText
{
	return [ NSArray array ];
}

/** Identifier for this text input instance. */
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
- (long)conversationIdentifier
#else
- (NSInteger)conversationIdentifier
#endif
{
	return 0;
}

/** Invoke the selector if we implement it. */
- (void)doCommandBySelector:(SEL)aSelector
{
	if ([ self respondsToSelector:aSelector ]) [ self performSelector:aSelector ];
}

@end



@implementation OTTD_CocoaWindowDelegate
/** Initialize the video driver */
- (void)setDriver:(CocoaSubdriver*)drv
{
	driver = drv;
}
/** Handle closure requests */
- (BOOL)windowShouldClose:(id)sender
{
	HandleExitGameRequest();

	return NO;
}
/** Handle key acceptance */
- (void)windowDidBecomeKey:(NSNotification*)aNotification
{
	driver->active = true;
}
/** Resign key acceptance */
- (void)windowDidResignKey:(NSNotification*)aNotification
{
	driver->active = false;
}
/** Handle becoming main window */
- (void)windowDidBecomeMain:(NSNotification*)aNotification
{
	driver->active = true;
}
/** Resign being main window */
- (void)windowDidResignMain:(NSNotification*)aNotification
{
	driver->active = false;
}
/** Window entered fullscreen mode (10.7). */
- (void)windowDidEnterFullScreen:(NSNotification *)aNotification
{
	NSPoint loc = [ driver->cocoaview convertPoint:[ [ aNotification object ] mouseLocationOutsideOfEventStream ] fromView:nil ];
	BOOL inside = ([ driver->cocoaview hitTest:loc ] == driver->cocoaview);

	if (inside) [ driver->cocoaview mouseEntered:NULL ];
}

@end

#endif /* WITH_COCOA */
