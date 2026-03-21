#import <Cocoa/Cocoa.h>

extern "C" bool setWindowTrafficLightsPosition(void *windowPtr, double x,
											   double yFromTop) {
	if (windowPtr == nullptr) {
		return false;
	}

	__block BOOL success = NO;
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSWindow *window = (__bridge NSWindow *)windowPtr;
		if (![window isKindOfClass:[NSWindow class]]) {
			return;
		}

		NSButton *closeButton =
			[window standardWindowButton:NSWindowCloseButton];
		NSButton *minimizeButton =
			[window standardWindowButton:NSWindowMiniaturizeButton];
		NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];

		if (closeButton == nil || minimizeButton == nil || zoomButton == nil) {
			return;
		}

		NSView *buttonContainer = [closeButton superview];
		if (buttonContainer == nil) {
			return;
		}

		CGFloat spacing = NSMinX(minimizeButton.frame) - NSMinX(closeButton.frame);
		if (spacing <= 0) {
			spacing = closeButton.frame.size.width + 6.0;
		}

		BOOL flipped = [buttonContainer isFlipped];
		CGFloat targetY = yFromTop;
		if (!flipped) {
			targetY = buttonContainer.frame.size.height - yFromTop -
					  closeButton.frame.size.height;
		}
		targetY = MAX(0.0, targetY);

		CGFloat currentX = x;
		NSArray<NSButton *> *buttons = @[ closeButton, minimizeButton, zoomButton ];
		for (NSButton *button in buttons) {
			[button setFrameOrigin:NSMakePoint(currentX, targetY)];
			currentX += spacing;
		}

		[buttonContainer setNeedsLayout:YES];
		[buttonContainer layoutSubtreeIfNeeded];
		success = YES;
	});

	return success;
}
