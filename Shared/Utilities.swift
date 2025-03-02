import SwiftUI
import Combine
import StoreKit
import GameplayKit
import UniformTypeIdentifiers
import Intents
import IntentsUI
import CoreBluetooth
import Contacts
import AudioToolbox

#if canImport(AppKit)
import IOKit.ps

typealias XColor = NSColor
typealias XFont = NSFont
typealias XImage = NSImage
typealias XPasteboard = NSPasteboard
typealias XApplication = NSApplication
typealias XApplicationDelegate = NSApplicationDelegate
typealias XApplicationDelegateAdaptor = NSApplicationDelegateAdaptor
#elseif canImport(UIKit)
typealias XColor = UIColor
typealias XFont = UIFont
typealias XImage = UIImage
typealias XPasteboard = UIPasteboard
typealias XApplication = UIApplication
typealias XApplicationDelegate = UIApplicationDelegate
typealias XApplicationDelegateAdaptor = UIApplicationDelegateAdaptor
#endif


// - MARK: Non-reusable utilities

#if canImport(UIKit)
extension HapticFeedbackType {
	var toNative: Device.HapticFeedback {
		switch self {
		case .unknown:
			return .legacy
		case .success:
			return .success
		case .warning:
			return .warning
		case .error:
			return .error
		case .selection:
			return .selection
		case .soft:
			return .soft
		case .light:
			return .light
		case .medium:
			return .medium
		case .heavy:
			return .heavy
		case .rigid:
			return .rigid
		}
	}
}
#endif

// MARK: -


// TODO: Remove this when everything is converted to async/await.
func delay(seconds: TimeInterval, closure: @escaping () -> Void) {
	DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: closure)
}


enum SSApp {
	static let id = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	static let versionWithBuild = "\(version) (\(build))"
	static let url = Bundle.main.bundleURL

	#if DEBUG
	static let isDebug = true
	#else
	static let isDebug = false
	#endif

	static var isDarkMode: Bool {
		#if canImport(AppKit)
			// The `effectiveAppearance` check does not detect dark mode in an intent handler extension.
			#if APP_EXTENSION
			return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
			#else
			return NSApp?.effectiveAppearance.isDarkMode ?? false
			#endif
		#elseif canImport(UIKit)
		return UIScreen.main.traitCollection.userInterfaceStyle == .dark
		#endif
	}

	#if canImport(AppKit)
	static func quit() {
		Task { @MainActor in
			NSApp.terminate(nil)
		}
	}
	#endif

	#if canImport(UIKit)
	/**
	Move the app to the background, which returns the user to their home screen.
	*/
	@available(iOSApplicationExtension, unavailable)
	static func moveToBackground() {
		Task { @MainActor in
			UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
		}
	}
	#endif

	static let isFirstLaunch: Bool = {
		let key = "SS_hasLaunched"

		if UserDefaults.standard.bool(forKey: key) {
			return false
		} else {
			UserDefaults.standard.set(true, forKey: key)
			return true
		}
	}()

	private static func getFeedbackMetadata() -> String {
		"""
		\(SSApp.name) \(SSApp.versionWithBuild) - \(SSApp.id)
		\(Device.operatingSystemString)
		\(Device.modelIdentifier)
		"""
	}

	static func openSendFeedbackPage() {
		let query: [String: String] = [
			"product": SSApp.name,
			"metadata": getFeedbackMetadata()
		]

		URL("https://sindresorhus.com/feedback/")
			.addingDictionaryAsQuery(query)
			.open()
	}

	static func sendFeedback(
		email: String,
		message: String
	) async throws {
		let endpoint = URL(string: "https://formcarry.com/s/UBfgr97yfY")!

		let parameters = [
			"_gotcha": nil, // Spam prevention.
			"timestamp": "\(Date.now.timeIntervalSince1970)",
			"product": SSApp.name,
			"metadata": getFeedbackMetadata(),
			"email": email.lowercased(),
			"message": message
		]

		_ = try await URLSession.shared.json(.post, url: endpoint, parameters: parameters as [String: Any])
	}
}


extension DispatchQueue {
	/**
	Performs the `execute` closure immediately if we're on the main thread or synchronously puts it on the main thread otherwise.
	*/
	@discardableResult
	static func mainSafeSync<T>(execute work: () throws -> T) rethrows -> T {
		if Thread.isMainThread {
			return try work()
		} else {
			return try main.sync(execute: work)
		}
	}
}


#if canImport(AppKit)
extension NSAppearance {
	var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
#endif


extension Data {
	var isNullTerminated: Bool { last == 0x0 }

	var withoutNullTerminator: Self {
		guard isNullTerminated else {
			return self
		}

		return dropLast()
	}

	/**
	Convert a null-terminated string data to a string.

	- Note: It gracefully handles if the string is not null-terminated.
	*/
	var stringFromNullTerminatedStringData: String? {
		String(data: withoutNullTerminator, encoding: .utf8)
	}
}


enum Device {
	#if canImport(AppKit)
	private static func ioPlatformExpertDevice(key: String) -> CFTypeRef? {
		let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
		defer {
			IOObjectRelease(service)
		}

		return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
	}
	#endif

	/**
	The name of the operating system running on the device.

	```
	Device.operatingSystemName
	//=> "macOS"

	Device.operatingSystemName
	//=> "iOS"
	```
	*/
	static let operatingSystemName: String = {
		#if canImport(AppKit)
		return "macOS"
		#elseif canImport(UIKit)
		return UIDevice.current.systemName
		#endif
	}()

	/**
	The version of the operating system running on the device.

	```
	// macOS
	Device.operatingSystemVersion
	//=> "10.14.2"

	// iOS
	Device.operatingSystemVersion
	//=> "13.5.1"
	```
	*/
	static let operatingSystemVersion: String = {
		#if canImport(AppKit)
		let os = ProcessInfo.processInfo.operatingSystemVersion
		return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
		#elseif canImport(UIKit)
		return UIDevice.current.systemVersion
		#endif
	}()

	/**
	The name and version of the operating system running on the device.

	```
	// macOS
	Device.operatingSystemString
	//=> "macOS 10.14.2"

	// iOS
	Device.operatingSystemString
	//=> "iOS 13.5.1"
	```
	*/
	static let operatingSystemString = "\(operatingSystemName) \(operatingSystemVersion)"

	/**
	```
	Device.modelIdentifier
	//=> "MacBookPro11,3"

	Device.modelIdentifier
	//=> "iPhone12,8"
	```
	*/
	static let modelIdentifier: String = {
		#if canImport(AppKit)
		guard
			let data = ioPlatformExpertDevice(key: "model") as? Data,
			let modelIdentifier = data.stringFromNullTerminatedStringData
		else {
			// This will most likely never happen.
			// So better to have a fallback than making it an optional.
			return "<Unknown model>"
		}

		return modelIdentifier
		#elseif targetEnvironment(simulator)
		return "Simulator"
		#elseif canImport(UIKit)
		var systemInfo = utsname()
		uname(&systemInfo)
		let machineMirror = Mirror(reflecting: systemInfo.machine)

		return machineMirror.children.reduce(into: "") { identifier, element in
			guard
				let value = element.value as? Int8,
				value != 0
			else {
				return
			}

			identifier += String(UnicodeScalar(UInt8(value)))
		}
		#endif
	}()

	/**
	Check if the device is connected to a VPN.
	*/
	@available(macOS, unavailable)
	static var isConnectedToVPN: Bool {
		guard
			let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as NSDictionary? as? [String: Any],
			let scoped = proxySettings["__SCOPED__"] as? [String: Any]
		else {
			return false
		}

		let vpnKeys = [
			"tap",
			"tun",
			"ppp",
			"ipsec",
			"utun"
		]

		return scoped.keys.contains { key in
			vpnKeys.contains { key.hasPrefix($0) }
		}
	}

	/**
	Whether the device has a small screen.

	This is useful for detecting iPhone SE and iPhone 6S, which has a very small screen and are still supported.

	On macOS, it always returns false.
	*/
	static let hasSmallScreen: Bool = {
		#if canImport(AppKit)
		return false
		#elseif canImport(UIKit)
		return UIScreen.main.bounds.height < 700
		#endif
	}()
}


#if canImport(AppKit)
enum InternalMacBattery {
	struct State {
		private static func powerSourceInfo() -> [String: AnyObject] {
			guard
				let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
				let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as [CFTypeRef]?,
				let source = sources.first,
				let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: AnyObject]
			else {
				return [:]
			}

			return description
		}

		/**
		Whether the device has a battery.
		*/
		let hasBattery: Bool

		/**
		Whether the power adapter is connected.
		*/
		let isPowerAdapterConnected: Bool

		/**
		Whether the battery is charging.
		*/
		let isCharging: Bool

		/**
		Whether the battery is fully charged and connected to a power adapter.
		*/
		let isCharged: Bool

		init() {
			let info = Self.powerSourceInfo()

			self.hasBattery = (info[kIOPSIsPresentKey] as? Bool) == true
				&& (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType

			if hasBattery {
				self.isPowerAdapterConnected = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
				self.isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
				self.isCharged = info[kIOPSIsChargedKey] as? Bool ?? false
			} else {
				self.isPowerAdapterConnected = true
				self.isCharging = false
				self.isCharged = false
			}
		}
	}

	/**
	The state of the internal battery.

	If the device does not have a battery, it still tries to return sensible values.
	*/
	static var state: State { .init() }
}
#endif


extension Device {
	enum BatteryState {
		/**
		The battery state for the device cannot be determined.
		*/
		case unknown

		/**
		The device is not plugged into power; the battery is discharging.
		*/
		case unplugged

		/**
		The device is plugged into power and the battery is less than 100% charged.
		*/
		case charging

		/**
		The device is plugged into power and the battery is 100% charged.
		*/
		case full
	}

	/**
	The state of the device's battery.
	*/
	static var batteryState: BatteryState {
		#if canImport(AppKit)
		let state = InternalMacBattery.state

		if state.isPowerAdapterConnected {
			if state.isCharged {
				return .full
			} else if state.isCharging {
				return .charging
			} else {
				return .unknown
			}
		} else {
			return .unplugged
		}
		#elseif canImport(UIKit)
		UIDevice.current.isBatteryMonitoringEnabled = true

		switch UIDevice.current.batteryState {
		case .unknown:
			return .unknown
		case .unplugged:
			return .unplugged
		case .charging:
			return .charging
		case .full:
			return .full
		@unknown default:
			return .unknown
		}
		#endif
	}
}


private func escapeQuery(_ query: String) -> String {
	// From RFC 3986
	let generalDelimiters = ":#[]@"
	let subDelimiters = "!$&'()*+,;="

	var allowedCharacters = CharacterSet.urlQueryAllowed
	allowedCharacters.remove(charactersIn: generalDelimiters + subDelimiters)
	return query.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? query
}


extension Dictionary where Key: ExpressibleByStringLiteral, Value: ExpressibleByStringLiteral {
	var asQueryItems: [URLQueryItem] {
		map {
			URLQueryItem(
				name: escapeQuery($0 as! String),
				value: escapeQuery($1 as! String)
			)
		}
	}

	var asQueryString: String {
		var components = URLComponents()
		components.queryItems = asQueryItems
		return components.query!
	}
}


extension URLComponents {
	mutating func addDictionaryAsQuery(_ dict: [String: String]) {
		percentEncodedQuery = dict.asQueryString
	}
}


extension URL {
	func addingDictionaryAsQuery(_ dict: [String: String]) -> Self {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
		components.addDictionaryAsQuery(dict)
		return components.url ?? self
	}
}


extension StringProtocol {
	/**
	Makes it easier to deal with optional sub-strings.
	*/
	var string: String { String(self) }
}


// swiftlint:disable:next no_cgfloat
extension CGFloat {
	/**
	Get a Double from a CGFloat. This makes it easier to work with optionals.
	*/
	var double: Double { Double(self) }
}

extension Int {
	/**
	Get a Double from an Int. This makes it easier to work with optionals.
	*/
	var double: Double { Double(self) }
}


private struct RespectDisabledViewModifier: ViewModifier {
	@Environment(\.isEnabled) private var isEnabled

	func body(content: Content) -> some View {
		content.opacity(isEnabled ? 1 : 0.5)
	}
}

extension Text {
	/**
	Make some text respect the current view environment being disabled.

	Useful for `Text` label to a control.
	*/
	func respectDisabled() -> some View {
		modifier(RespectDisabledViewModifier())
	}
}


extension URL {
	/**
	Convenience for opening URLs.
	*/
	func open() {
		#if canImport(AppKit)
		NSWorkspace.shared.open(self)
		#elseif canImport(UIKit) && !APP_EXTENSION
		Task { @MainActor in
			UIApplication.shared.open(self)
		}
		#endif
	}
}


extension String {
	/*
	```
	"https://sindresorhus.com".openUrl()
	```
	*/
	func openUrl() {
		URL(string: self)?.open()
	}
}


extension URL: ExpressibleByStringLiteral {
	/**
	Example:

	```
	let url: URL = "https://sindresorhus.com"
	```
	*/
	public init(stringLiteral value: StaticString) {
		self.init(string: "\(value)")!
	}
}


extension URL {
	/**
	Example:

	```
	URL("https://sindresorhus.com")
	```
	*/
	init(_ staticString: StaticString) {
		self.init(string: "\(staticString)")!
	}
}


#if canImport(AppKit)
private struct WindowAccessor: NSViewRepresentable {
	private final class WindowAccessorView: NSView {
		@Binding var windowBinding: NSWindow?

		init(binding: Binding<NSWindow?>) {
			self._windowBinding = binding
			super.init(frame: .zero)
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			windowBinding = window
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError() // swiftlint:disable:this fatal_error_message
		}
	}

	@Binding var window: NSWindow?

	init(_ window: Binding<NSWindow?>) {
		self._window = window
	}

	func makeNSView(context: Context) -> NSView {
		WindowAccessorView(binding: $window)
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
	/**
	Bind the native backing-window of a SwiftUI window to a property.
	*/
	func bindNativeWindow(_ window: Binding<NSWindow?>) -> some View {
		background(WindowAccessor(window))
	}
}

private struct WindowViewModifier: ViewModifier {
	@State private var window: NSWindow?

	let onWindow: (NSWindow?) -> Void

	func body(content: Content) -> some View {
		onWindow(window)

		return content
			.bindNativeWindow($window)
	}
}

extension View {
	/**
	Access the native backing-window of a SwiftUI window.
	*/
	func accessNativeWindow(_ onWindow: @escaping (NSWindow?) -> Void) -> some View {
		modifier(WindowViewModifier(onWindow: onWindow))
	}

	/**
	Set the window level of a SwiftUI window.
	*/
	func windowLevel(_ level: NSWindow.Level) -> some View {
		accessNativeWindow {
			$0?.level = level
		}
	}
}
#endif


/**
Useful in SwiftUI:

```
ForEach(persons.indexed(), id: \.1.id) { index, person in
	// …
}
```
*/
struct IndexedCollection<Base: RandomAccessCollection>: RandomAccessCollection {
	typealias Index = Base.Index
	typealias Element = (index: Index, element: Base.Element)

	let base: Base
	var startIndex: Index { base.startIndex }
	var endIndex: Index { base.endIndex }

	func index(after index: Index) -> Index {
		base.index(after: index)
	}

	func index(before index: Index) -> Index {
		base.index(before: index)
	}

	func index(_ index: Index, offsetBy distance: Int) -> Index {
		base.index(index, offsetBy: distance)
	}

	subscript(position: Index) -> Element {
		(index: position, element: base[position])
	}
}

extension RandomAccessCollection {
	/**
	Returns a sequence with a tuple of both the index and the element.

	- Important: Use this instead of `.enumerated()`. See: https://khanlou.com/2017/03/you-probably-don%27t-want-enumerated/
	*/
	func indexed() -> IndexedCollection<Self> {
		IndexedCollection(base: self)
	}
}


extension Numeric {
	mutating func increment(by value: Self = 1) -> Self {
		self += value
		return self
	}

	mutating func decrement(by value: Self = 1) -> Self {
		self -= value
		return self
	}

	func incremented(by value: Self = 1) -> Self {
		self + value
	}

	func decremented(by value: Self = 1) -> Self {
		self - value
	}
}


// TODO
//extension SSApp {
//	private static let key = Defaults.Key("SSApp_requestReview", default: 0)
//
//	/**
//	Requests a review only after this method has been called the given amount of times.
//	*/
//	static func requestReviewAfterBeingCalledThisManyTimes(_ counts: [Int]) {
//		guard
//			!SSApp.isFirstLaunch,
//			counts.contains(Defaults[key].increment())
//		else {
//			return
//		}
//
//		SKStoreReviewController.requestReview()
//	}
//}


#if canImport(AppKit)
extension NSImage {
	/**
	Draw a color as an image.
	*/
	static func color(
		_ color: NSColor,
		size: CGSize,
		borderWidth: Double = 0,
		borderColor: NSColor? = nil,
		cornerRadius: Double? = nil
	) -> Self {
		Self(size: size, flipped: false) { bounds in
			NSGraphicsContext.current?.imageInterpolation = .high

			guard let cornerRadius = cornerRadius else {
				color.drawSwatch(in: bounds)
				return true
			}

			let targetRect = bounds.insetBy(
				dx: borderWidth,
				dy: borderWidth
			)

			let bezierPath = NSBezierPath(
				roundedRect: targetRect,
				xRadius: cornerRadius,
				yRadius: cornerRadius
			)

			color.set()
			bezierPath.fill()

			if
				borderWidth > 0,
				let borderColor = borderColor
			{
				borderColor.setStroke()
				bezierPath.lineWidth = borderWidth
				bezierPath.stroke()
			}

			return true
		}
	}
}
#elseif canImport(UIKit)
extension UIImage {
	static func color(
		_ color: UIColor,
		size: CGSize,
		scale: Double? = nil
	) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.opaque = true

		if let scale = scale {
			format.scale = scale
		}

		return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
			color.setFill()
			rendererContext.fill(CGRect(origin: .zero, size: size))
		}
	}
}
#endif


extension SSApp {
	/**
	This is like `SSApp.runOnce()` but let's you have an else-statement too.

	```
	if SSApp.runOnceShouldRun(identifier: "foo") {
		// True only the first time and only once.
	} else {

	}
	```
	*/
	static func runOnceShouldRun(identifier: String) -> Bool {
		let key = "SS_App_runOnce__\(identifier)"

		guard !UserDefaults.standard.bool(forKey: key) else {
			return false
		}

		UserDefaults.standard.set(true, forKey: key)
		return true
	}

	/**
	Run a closure only once ever, even between relaunches of the app.
	*/
	static func runOnce(identifier: String, _ execute: () -> Void) {
		guard runOnceShouldRun(identifier: identifier) else {
			return
		}

		execute()
	}
}


extension Collection {
	func appending(_ newElement: Element) -> [Element] {
		self + [newElement]
	}

	func prepending(_ newElement: Element) -> [Element] {
		[newElement] + self
	}
}


extension Collection {
	var nilIfEmpty: Self? { isEmpty ? nil : self }
}

extension StringProtocol {
	var nilIfEmptyOrWhitespace: Self? { isEmptyOrWhitespace ? nil : self }
}

extension AdditiveArithmetic {
	/**
	Return `nil` if the value is `0`.
	*/
	var nilIfZero: Self? { self == .zero ? nil : self }
}


extension View {
	func multilineText() -> some View {
		lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
	}
}


private struct SecondaryTextStyleModifier: ViewModifier {
	@ScaledMetric private var fontSize = XFont.smallSystemFontSize

	func body(content: Content) -> some View {
		content
			.font(.system(size: fontSize))
			.foregroundStyle(.secondary)
	}
}

extension View {
	func secondaryTextStyle() -> some View {
		modifier(SecondaryTextStyleModifier())
	}
}


extension View {
	/**
	Usually used for a verbose description of a settings item.
	*/
	func settingSubtitleTextStyle() -> some View {
		secondaryTextStyle()
			.multilineText()
	}
}


extension String {
	/**
	Returns a random emoticon (part of emojis).

	See: https://en.wikipedia.org/wiki/Emoticons_(Unicode_block)
	*/
	static func randomEmoticon() -> Self {
		let scalarValue = Int.random(in: 0x1F600...0x1F64F)

		guard let scalar = Unicode.Scalar(scalarValue) else {
			// This should in theory never be hit.
			assertionFailure()
			return ""
		}

		return String(scalar)
	}
}


extension Character {
	var isSimpleEmoji: Bool {
		guard let firstScalar = unicodeScalars.first else {
			return false
		}

		return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
	}

	var isCombinedIntoEmoji: Bool {
		unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false
	}

	var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}


extension String {
	/**
	Get all the emojis in the string.

	```
	"foo🦄bar🌈👩‍👩‍👦‍👦".emojis
	//=> ["🦄", "🌈", "👩‍👩‍👦‍👦"]
	```
	*/
	var emojis: [Character] { filter(\.isEmoji) }
}


extension String {
	/**
	Returns a version of the string without emojis.

	```
	"foo🦄✈️bar🌈👩‍👩‍👦‍👦".removingEmojis()
	//=> "foobar"
	```
	*/
	func removingEmojis() -> Self {
		Self(filter { !$0.isEmoji })
	}
}


extension Date {
	/**
	Returns a random `Date` within the given range.

	```
	Date.random(in: Date.now...Date.now.addingTimeInterval(10000))
	```
	*/
	static func random(in range: ClosedRange<Self>) -> Self {
		let timeIntervalRange = range.lowerBound.timeIntervalSinceNow...range.upperBound.timeIntervalSinceNow
		return Self(timeIntervalSinceNow: .random(in: timeIntervalRange))
	}
}


extension DateComponents {
	/**
	Returns a random `DateComponents` within the given range.

	The `start` can be after or before `end`.

	```
	let start = Calendar.current.dateComponents(in: .current, from: .now)
	let end = Calendar.current.dateComponents(in: .current, from: .now.addingTimeInterval(1000))
	DateComponents.random(start: start, end: end, for: .current)?.date
	```
	*/
	static func random(start: Self, end: Self, for calendar: Calendar) -> Self? {
		guard
			let startDate = start.date,
			let endDate = end.date
		else {
			return nil
		}

		return calendar.dateComponents(in: .current, from: .random(in: .fromGraceful(startDate, endDate)))
	}
}


extension ClosedRange {
	/**
	Create a `ClosedRange` where it does not matter which bound is upper and lower.

	Using a range literal would hard crash if the lower bound is higher than the upper bound.
	*/
	static func fromGraceful(_ bound1: Bound, _ bound2: Bound) -> Self {
		bound1 <= bound2 ? bound1...bound2 : bound2...bound1
	}
}


enum SortType {
	/**
	This sorting method should be used whenever file names or other strings are presented in lists and tables where Finder-like sorting is appropriate.
	*/
	case natural

	case localized
	case localizedCaseInsensitive
}

extension Sequence where Element: StringProtocol {
	// TODO: Use the new macOS 12, `SortComparator` stuff here: https://developer.apple.com/documentation/foundation/sortcomparator
	// https://developer.apple.com/documentation/swift/sequence/3802502-sorted#
	/**
	Sort a collection of strings.

	```
	let x = ["Kofi", "Abena", "Peter", "Kweku", "Akosua", "abena", "bee", "ábenā"]

	x.sorted(type: .natural)
	//=> ["abena", "Abena", "ábenā", "Akosua", "bee", "Kofi", "Kweku", "Peter"]

	x.sorted(type: .localized)
	//=> ["abena", "Abena", "ábenā", "Akosua", "bee", "Kofi", "Kweku", "Peter"]

	x.sorted(type: .localizedCaseInsensitive)
	//=> ["Abena", "abena", "ábenā", "Akosua", "bee", "Kofi", "Kweku", "Peter"]

	x.sorted()
	//=> ["Abena", "Akosua", "Kofi", "Kweku", "Peter", "abena", "bee", "ábenā"]
	```
	*/
	func sorted(type: SortType, order: SortOrder = .forward) -> [Element] {
		let comparisonResult = order == .forward ? ComparisonResult.orderedAscending : .orderedDescending

		switch type {
		case .natural:
			return sorted { $0.localizedStandardCompare($1) == comparisonResult }
		case .localized:
			return sorted { $0.localizedCompare($1) == comparisonResult }
		case .localizedCaseInsensitive:
			return sorted { $0.localizedCaseInsensitiveCompare($1) == comparisonResult }
		}
	}
}


extension Sequence where Element: StringProtocol {
	/**
	Returns an array with duplicate strings removed, by comparing the string using localized comparison.

	- Parameters:
	  - caseInsensitive: Ignore the case of the characters when comparing.
	  - overrideInclusion: Lets you decide if an individual element should be force included or excluded. This can be useful to, for example, force include multiple empty string elements, which would otherwise be considered duplicates.

	```
	["a", "A", "b", "B"].localizedRemovingDuplicates(caseInsensitive: true)
	//=> ["a", "b"]
	```
	*/
	func localizedRemovingDuplicates(
		caseInsensitive: Bool = false,
		// TODO: Need a better name for this parameter.
		overrideInclusion: ((Element) -> Bool?)? = nil // swiftlint:disable:this discouraged_optional_boolean
	) -> [Element] {
		reduce(into: []) { result, element in
			if let shouldInclude = overrideInclusion?(element) {
				if shouldInclude {
					result.append(element)
				}
				return
			}

			let contains = result.contains {
				caseInsensitive
					? $0.localizedCaseInsensitiveCompare(element) == .orderedSame
					: $0.localizedCompare(element) == .orderedSame
			}

			if !contains {
				result.append(element)
			}
		}
	}
}


extension String {
	/**
	Returns a string with duplicate lines removed, by using localized comparison.

	Empty and whitespace-only lines are preserved.
	*/
	func localizedRemovingDuplicateLines(caseInsensitive: Bool = false) -> Self {
		lines()
			.localizedRemovingDuplicates(caseInsensitive: caseInsensitive) {
				if $0.isEmptyOrWhitespace {
					return true
				}

				return nil
			}
			.joined(separator: "\n")
	}
}


extension Sequence {
	/**
	Returns an array with duplicates removed by checking for duplicates based on the given key path.

	```
	let a = [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 2)]
	let b = a.removingDuplicates(by: \.y)
	//=> [CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)]
	```
	*/
	func removingDuplicates<T: Equatable>(by keyPath: KeyPath<Element, T>) -> [Element] {
		var result = [Element]()
		var seen = [T]()
		for value in self {
			let key = value[keyPath: keyPath]
			if !seen.contains(key) {
				seen.append(key)
				result.append(value)
			}
		}
		return result
	}

	/**
	Returns an array with duplicates removed by checking for duplicates based on the given key path.

	```
	let a = [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 2)]
	let b = a.removingDuplicates(by: \.y)
	//=> [CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)]
	```
	*/
	func removingDuplicates<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
		var seenKeys = Set<T>()
		return filter { seenKeys.insert($0[keyPath: keyPath]).inserted }
	}
}


extension String {
	/**
	Returns a version of the string with the first character lowercased.
	*/
	var lowercasedFirstCharacter: String {
		prefix(1).lowercased() + dropFirst()
	}

	/**
	Returns a version of the string transformed to pascal case.
	*/
	func pascalCasing() -> Self {
		guard !isEmpty else {
			return ""
		}

		return components(separatedBy: .alphanumerics.inverted)
			.map(\.capitalized)
			.joined()
	}

	/**
	Returns a version of the string transformed to pascal case.
	*/
	func camelCasing() -> Self {
		guard !isEmpty else {
			return ""
		}

		return pascalCasing().lowercasedFirstCharacter
	}

	private func delimiterCasing(delimiter: String) -> String {
		guard !isEmpty else {
			return ""
		}

		return components(separatedBy: .alphanumerics.inverted)
			.filter { !$0.isEmpty }
			.map { $0.lowercased() }
			.joined(separator: delimiter)
	}

	/**
	Returns a version of the string transformed to snake case.
	*/
	func snakeCasing() -> String {
		delimiterCasing(delimiter: "_")
	}

	/**
	Returns a version of the string transformed to constant case.
	*/
	func constantCasing() -> String {
		snakeCasing().uppercased()
	}

	/**
	Returns a version of the string transformed to dash case.
	*/
	func dashCasing() -> String {
		delimiterCasing(delimiter: "-")
	}
}


extension Comparable {
	/**
	```
	20.5.clamped(to: 10.3...15)
	//=> 15
	```
	*/
	func clamped(to range: ClosedRange<Self>) -> Self {
		min(max(self, range.lowerBound), range.upperBound)
	}
}


extension StringProtocol {
	/**
	Check if the string only contains whitespace characters.
	*/
	var isWhitespace: Bool {
		allSatisfy(\.isWhitespace)
	}

	/**
	Check if the string is empty or only contains whitespace characters.
	*/
	var isEmptyOrWhitespace: Bool { isEmpty || isWhitespace }
}


extension String {
	func lines() -> [Self] {
		components(separatedBy: .newlines)
	}
}


extension String {
	/**
	Returns a string with empty or whitespace-only lines removed.
	*/
	func removingEmptyLines() -> Self {
		lines()
			.filter { !$0.isEmptyOrWhitespace }
			.joined(separator: "\n")
	}
}


extension XColor {
	/**
	Generate a random color, avoiding black and white.
	*/
	static func randomAvoidingBlackAndWhite() -> Self {
		self.init(
			hue: .random(in: 0...1),
			saturation: .random(in: 0.5...1), // 0.5 is to get away from white
			brightness: .random(in: 0.5...1), // 0.5 is to get away from black
			alpha: 1
		)
	}
}


#if canImport(UIKit)
// swiftlint:disable no_cgfloat
extension UIColor {
	/**
	AppKit polyfill.

	The alpha (opacity) component value of the color.
	*/
	var alphaComponent: CGFloat {
		var alpha: CGFloat = 0
		getRed(nil, green: nil, blue: nil, alpha: &alpha)
		return alpha
	}

	var redComponent: CGFloat {
		var red: CGFloat = 0
		getRed(&red, green: nil, blue: nil, alpha: nil)
		return red
	}

	var greenComponent: CGFloat {
		var green: CGFloat = 0
		getRed(nil, green: &green, blue: nil, alpha: nil)
		return green
	}

	var blueComponent: CGFloat {
		var blue: CGFloat = 0
		getRed(nil, green: nil, blue: &blue, alpha: nil)
		return blue
	}
}
// swiftlint:enable no_cgfloat
#endif


extension XColor {
	/**
	- Important: Don't forget to convert it to the correct color space first.
	*/
	var hex: Int {
		#if canImport(AppKit)
		guard numberOfComponents == 4 else {
			assertionFailure()
			return 0x0
		}
		#endif

		let red = Int((redComponent * 0xFF).rounded())
		let green = Int((greenComponent * 0xFF).rounded())
		let blue = Int((blueComponent * 0xFF).rounded())

		return red << 16 | green << 8 | blue
	}

	/**
	- Important: Don't forget to convert it to the correct color space first.
	*/
	var hexString: String {
		String(format: "#%06x", hex)
	}
}


extension String {
	/**
	Check if the string starts with the given prefix and prepend it if not.

	```
	" Bar".ensurePrefix("Foo")
	//=> "Foo Bar"
	"Foo Bar".ensurePrefix("Foo")
	//=> "Foo Bar"
	```
	*/
	func ensurePrefix(_ prefix: Self) -> Self {
		hasPrefix(prefix) ? self : (prefix + self)
	}

	/**
	Check if the string ends with the given suffix and append it if not.

	```
	"Foo ".ensureSuffix("Bar")
	//=> "Foo Bar"
	"Foo Bar".ensureSuffix("Bar")
	//=> "Foo Bar"
	```
	*/
	func ensureSuffix(_ suffix: Self) -> Self {
		hasSuffix(suffix) ? self : (self + suffix)
	}
}


extension StringProtocol {
	/**
	```
	"foo bar".replacingPrefix("foo", with: "unicorn")
	//=> "unicorn bar"
	```
	*/
	func replacingPrefix(_ prefix: String, with replacement: String) -> String {
		guard hasPrefix(prefix) else {
			return String(self)
		}

		return replacement + dropFirst(prefix.count)
	}

	/**
	```
	"foo bar".replacingSuffix("bar", with: "unicorn")
	//=> "foo unicorn"
	```
	*/
	func replacingSuffix(_ suffix: String, with replacement: String) -> String {
		guard hasSuffix(suffix) else {
			return String(self)
		}

		return dropLast(suffix.count) + replacement
	}
}


extension URL {
	/**
	Returns the user's real home directory when called in a sandboxed app.
	*/
	static let realHomeDirectory = Self(
		fileURLWithFileSystemRepresentation: getpwuid(getuid())!.pointee.pw_dir!,
		isDirectory: true,
		relativeTo: nil
	)
}


extension URL {
	var tildePath: String {
		// Note: Can't use `FileManager.default.homeDirectoryForCurrentUser.relativePath` or `NSHomeDirectory()` here as they return the sandboxed home directory, not the real one.
		path.replacingPrefix(Self.realHomeDirectory.path, with: "~")
	}
}


extension Sequence {
	/**
	Returns an array of elements split into groups of the given size.

	If it can't be split evenly, the final chunk will be the remaining elements.

	If the requested chunk size is larger than the sequence, the chunk will be smaller than requested.

	```
	[1, 2, 3, 4].chunked(by: 2)
	//=> [[1, 2], [3, 4]]
	```
	*/
	func chunked(by chunkSize: Int) -> [[Element]] {
		guard chunkSize > 0 else {
			return []
		}

		return reduce(into: []) { result, current in
			if
				let last = result.last,
				last.count < chunkSize
			{
				result.append(result.removeLast() + [current])
			} else {
				result.append([current])
			}
		}
	}
}


extension Collection {
	/**
	Returns the element at the specified index if it is within bounds, otherwise `nil`.
	*/
	subscript(safe index: Index) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}


extension Collection {
	/**
	Returns the second element if it exists, otherwise `nil`.
	*/
	var second: Element? {
		self[safe: index(startIndex, offsetBy: 1)]
	}
}


#if !APP_EXTENSION
enum ShortcutsApp {
	@MainActor
	static func open() {
		"shortcuts://".openUrl()
	}

	@MainActor
	static func createShortcut() {
		"shortcuts://create-shortcut".openUrl()
	}
}
#endif


enum OperatingSystem {
	case macOS
	case iOS
	case tvOS
	case watchOS

	#if os(macOS)
	static let current = macOS
	#elseif os(iOS)
	static let current = iOS
	#elseif os(tvOS)
	static let current = tvOS
	#elseif os(watchOS)
	static let current = watchOS
	#else
	#error("Unsupported platform")
	#endif
}

typealias OS = OperatingSystem

extension View {
	/**
	Conditionally apply modifiers depending on the target operating system.

	```
	struct ContentView: View {
		var body: some View {
			Text("Unicorn")
				.font(.system(size: 10))
				.ifOS(.macOS, .tvOS) {
					$0.font(.system(size: 20))
				}
		}
	}
	```
	*/
	@ViewBuilder
	func ifOS<Content: View>(
		_ operatingSystems: OperatingSystem...,
		modifier: (Self) -> Content
	) -> some View {
		if operatingSystems.contains(.current) {
			modifier(self)
		} else {
			self
		}
	}
}


extension View {
	/**
	Embed the view in a scroll view.
	*/
	@ViewBuilder
	func embedInScrollView(shouldEmbed: Bool = true, alignment: Alignment = .center) -> some View {
		if shouldEmbed {
			GeometryReader { proxy in
				ScrollView {
					frame(
						minHeight: proxy.size.height,
						maxHeight: .infinity,
						alignment: alignment
					)
				}
			}
		} else {
			self
		}
	}
}


private struct EmbedInScrollViewIfAccessibilitySizeModifier: ViewModifier {
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	let alignment: Alignment

	func body(content: Content) -> some View {
		content.embedInScrollView(shouldEmbed: dynamicTypeSize.isAccessibilitySize, alignment: alignment)
	}
}

extension View {
	/**
	Embed the view in a scroll view if the system has accessibility dynamic type enabled.
	*/
	func embedInScrollViewIfAccessibilitySize(alignment: Alignment = .center) -> some View {
		modifier(EmbedInScrollViewIfAccessibilitySizeModifier(alignment: alignment))
	}
}


private struct ActuallyHiddenIfAccessibilitySizeModifier: ViewModifier {
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	func body(content: Content) -> some View {
		if !dynamicTypeSize.isAccessibilitySize {
			content
		}
	}
}

extension View {
	/**
	Excludes the view from the hierarchy if the device has enabled accessibility size text.
	*/
	func actuallyHiddenIfAccessibilitySize() -> some View {
		modifier(ActuallyHiddenIfAccessibilitySizeModifier())
	}
}


/**
Modern alternative to `OptionSet`.

Just use an enum instead.

```
typealias Toppings = Set<Topping>

enum Topping: String, Option {
	case pepperoni
	case onions
	case bacon
	case extraCheese
	case greenPeppers
	case pineapple
}
```
*/
protocol Option: RawRepresentable, Hashable, CaseIterable {}

extension Set where Element: Option {
	var rawValue: Int {
		var rawValue = 0
		for (index, element) in Element.allCases.enumerated() {
			if contains(element) {
				rawValue |= (1 << index)
			}
		}

		return rawValue
	}

	var description: String {
		map { String(describing: $0) }.joined(separator: ", ")
	}
}


extension String {
	/**
	Returns a persistent non-crypto hash of the string in the fastest way possible.

	- Note: This exists as `.hashValue` is not guaranteed to be equal across different executions of your program.
	*/
	var persistentHash: UInt64 {
		var result: UInt64 = 5381
		let buffer = [UInt8](utf8)

		for element in buffer {
			result = 127 * (result & 0x00FF_FFFF_FFFF_FFFF) + UInt64(element)
		}

		return result
	}
}


extension RandomNumberGenerator where Self == SystemRandomNumberGenerator {
	/**
	```
	random(length: length, using: &.system)
	```
	*/
	static var system: Self {
		get { .init() }
		set {} // swiftlint:disable:this unused_setter_value
	}
}


/**
A type-erased random number generator.
*/
struct AnyRandomNumberGenerator: RandomNumberGenerator {
	@usableFromInline
	var enclosed: RandomNumberGenerator

	@inlinable
	init(_ enclosed: RandomNumberGenerator) {
		self.enclosed = enclosed
	}

	@inlinable
	mutating func next() -> UInt64 {
		enclosed.next()
	}
}

extension RandomNumberGenerator {
	/**
	Type-erase the random number generator.
	*/
	func eraseToAny() -> AnyRandomNumberGenerator {
		AnyRandomNumberGenerator(self)
	}
}


#if !os(watchOS)
struct SeededRandomNumberGenerator: RandomNumberGenerator {
	private let source: GKMersenneTwisterRandomSource

	init(seed: UInt64) {
		self.source = GKMersenneTwisterRandomSource(seed: seed)
	}

	init(seed: String) {
		self.init(seed: seed.persistentHash)
	}

	func next() -> UInt64 {
		let next1 = UInt64(bitPattern: Int64(source.nextInt()))
		let next2 = UInt64(bitPattern: Int64(source.nextInt()))
		return next1 ^ (next2 << 32)
	}
}
#endif


extension String {
	enum RandomCharacter: String, Option {
		case lowercase
		case uppercase
		case digits
	}

	typealias RandomCharacters = Set<RandomCharacter>

	/**
	Generate a random ASCII string from a custom set of characters.

	```
	String.random(length: 10, characters: "abc123")
	//=> "ca32aab12c"
	```
	*/
	static func random<T>(
		length: Int,
		characters: String,
		using generator: inout T
	) -> Self where T: RandomNumberGenerator {
		precondition(!characters.isEmpty)
		return Self((0..<length).map { _ in characters.randomElement(using: &generator)! })
	}

	/**
	Generate a random ASCII string from a custom set of characters.

	```
	String.random(length: 10, characters: "abc123")
	//=> "ca32aab12c"
	```
	*/
	static func random(
		length: Int,
		characters: String
	) -> Self {
		random(length: length, characters: characters, using: &.system)
	}

	/**
	Generate a random ASCII string.

	```
	String.random(length: 10, characters: [.lowercase])
	//=> "czzet1fv6d"
	```
	*/
	static func random<T>(
		length: Int,
		characters: RandomCharacters = [.lowercase, .uppercase, .digits],
		using generator: inout T
	) -> Self where T: RandomNumberGenerator {
		var characterString = ""

		if characters.contains(.lowercase) {
			characterString += "abcdefghijklmnopqrstuvwxyz"
		}

		if characters.contains(.uppercase) {
			characterString += "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		}

		if characters.contains(.digits) {
			characterString += "0123456789"
		}

		return random(length: length, characters: characterString, using: &generator)
	}

	/**
	Generate a random ASCII string.

	```
	String.random(length: 10, characters: [.lowercase])
	//=> "czzetefvgd"
	```
	*/
	static func random(
		length: Int,
		characters: RandomCharacters = [.lowercase, .uppercase, .digits]
	) -> Self {
		random(length: length, characters: characters, using: &.system)
	}
}


extension RangeReplaceableCollection {
	func removingSubrange<R>(_ bounds: R) -> Self where R: RangeExpression, Index == R.Bound {
		var copy = self
		copy.removeSubrange(bounds)
		return copy
	}
}


extension Collection {
	/**
	Returns a sequence with a tuple of both the index and the element.
	*/
	func indexed() -> Zip2Sequence<Indices, Self> {
		zip(indices, self)
	}
}


extension Collection where Index: Hashable {
	/**
	Returns an array with elements at the given offsets (indices) removed.

	Invalid indices are ignored.

	```
	[1, 2, 3, 4].removing(atIndices: [0, 3])
	//=> [2, 3]
	```

	See the built-in `remove(atOffset:)` for a mutable version.
	*/
	func removing(atIndices indices: [Index]) -> [Element] {
		let indiceSet = Set(indices)
		return indexed().filter { !indiceSet.contains($0.0) }.map(\.1)
	}
}


extension Locale {
	/**
	Unix representation of locale usually used for normalizing.
	*/
	static let posix = Self(identifier: "en_US_POSIX")
}


extension URL {
	private func resourceValue<T>(forKey key: URLResourceKey) -> T? {
		guard let values = try? resourceValues(forKeys: [key]) else {
			return nil
		}

		return values.allValues[key] as? T
	}

	/**
	Set multiple resources values in one go.

	```
	try destinationURL.setResourceValues {
		if let creationDate = creationDate {
			$0.creationDate = creationDate
		}

		if let modificationDate = modificationDate {
			$0.contentModificationDate = modificationDate
		}
	}
	```
	*/
	func setResourceValues(with closure: (inout URLResourceValues) -> Void) throws {
		var copy = self
		var values = URLResourceValues()
		closure(&values)
		try copy.setResourceValues(values)
	}

	var contentType: UTType? { resourceValue(forKey: .contentTypeKey) }
}


extension CGImage {
	/**
	Get metadata from an image on disk.

	- Returns: `CGImageProperties` https://developer.apple.com/documentation/imageio/cgimageproperties
	*/
	static func metadata(_ url: URL) -> [String: Any] {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			return [:]
		}

		return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
	}

	/**
	Get metadata from an image in memory.

	- Returns: `CGImageProperties` https://developer.apple.com/documentation/imageio/cgimageproperties
	*/
	static func metadata(_ data: Data) -> [String: Any] {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
			return [:]
		}

		return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
	}
}


extension URL {
	/**
	Creates a unique temporary directory and returns the URL.

	The URL is unique for each call.

	The system ensures the directory is not cleaned up until after the app quits.
	*/
	static func uniqueTemporaryDirectory(
		appropriateFor: Self = Bundle.main.bundleURL
	) throws -> Self {
		try FileManager.default.url(
			for: .itemReplacementDirectory,
			in: .userDomainMask,
			appropriateFor: appropriateFor,
			create: true
		)
	}

	/**
	Copy the file at the current URL to a unique temporary directory and return the new URL.
	*/
	func copyToUniqueTemporaryDirectory() throws -> Self {
		let destinationUrl = try Self.uniqueTemporaryDirectory(appropriateFor: self)
			.appendingPathComponent(lastPathComponent, isDirectory: false)

		try FileManager.default.copyItem(at: self, to: destinationUrl)

		return destinationUrl
	}
}


extension Data {
	/**
	Write the data to a unique temporary path and return the `URL`.

	By default, the file has no file extension.
	*/
	func writeToUniqueTemporaryFile(
		filename: String = "file",
		contentType: UTType = .data
	) throws -> URL {
		let destinationUrl = try URL.uniqueTemporaryDirectory()
			.appendingPathComponent(filename, conformingTo: contentType)

		try write(to: destinationUrl)

		return destinationUrl
	}
}


extension CGImage {
	// TODO: Use the modern macOS 12 API for parsing dates.
	static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = .posix
		formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
		return formatter
	}()

	private static func captureDateFromMetadata(_ metadata: [String: Any]) -> Date? {
		guard
			let exifDictionary = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
			let dateTimeOriginal = exifDictionary[kCGImagePropertyExifDateTimeOriginal as String] as? String,
			let captureDate = dateFormatter.date(from: dateTimeOriginal)
		else {
			return nil
		}

		return captureDate
	}

	/**
	Returns the original capture date & time from the Exif metadata of the image at the given URL.
	*/
	static func captureDate(ofImageAt url: URL) -> Date? {
		captureDateFromMetadata(metadata(url))
	}

	/**
	Returns the original capture date & time from the Exif metadata of the image data.
	*/
	static func captureDate(ofImage data: Data) -> Date? {
		captureDateFromMetadata(metadata(data))
	}
}


extension INFile {
	var contentType: UTType? {
		guard let typeIdentifier = typeIdentifier else {
			return nil
		}

		return UTType(typeIdentifier)
	}
}


extension INFile {
	/**
	Write the data to a unique temporary path and return the `URL`.
	*/
	func writeToUniqueTemporaryFile() throws -> URL {
		try data.writeToUniqueTemporaryFile(
			filename: filename,
			contentType: contentType ?? .data
		)
	}
}


extension INFile {
	/**
	Gives you a copy of the file written to disk which you can modify as you please.

	You are expected to return a file URL to the same or a different file.

	- Note: If you just need to modify the data, access `.data` instead.

	Use-cases:
	- Change modification date of a file.
	- Set Exif metadata.
	- Convert to a different file type.

	We intentionally do not use `.fileURL` as accessing it when the file is, for example, in the `Downloads` directory, causes a permission prompt on macOS, which requires manual interaction.
	*/
	func modifyingFileAsURL(_ modify: (URL) throws -> URL) throws -> INFile {
		try modify(writeToUniqueTemporaryFile()).toINFile
	}
}


extension URL {
	/**
	Create a `INFile` from the URL.
	*/
	var toINFile: INFile {
		INFile(
			fileURL: self,
			filename: lastPathComponent,
			typeIdentifier: contentType?.identifier
		)
	}
}


extension XImage {
	/**
	Create a `INFile` from the image.
	*/
	var toINFile: INFile? {
		#if canImport(AppKit)
		try? tiffRepresentation?
			.writeToUniqueTemporaryFile(contentType: .tiff)
			.toINFile
		#elseif canImport(UIKit)
		try? pngData()?
			.writeToUniqueTemporaryFile(contentType: .png)
			.toINFile
		#endif
	}
}


extension Sequence {
	func compact<T>() -> [T] where Element == T? {
		// TODO: Make this `compactMap(\.self)` when https://bugs.swift.org/browse/SR-12897 is fixed.
		compactMap { $0 }
	}
}


extension Sequence where Element: Sequence {
	func flatten() -> [Element.Element] {
		// TODO: Make this `flatMap(\.self)` when https://bugs.swift.org/browse/SR-12897 is fixed.
		flatMap { $0 }
	}
}


extension NSRegularExpression {
	func matches(_ string: String) -> Bool {
		let range = NSRange(location: 0, length: string.utf16.count)
		return firstMatch(in: string, options: [], range: range) != nil
	}
}


extension URLResponse {
	/**
	Get the `HTTPURLResponse`.
	*/
	var http: HTTPURLResponse? { self as? HTTPURLResponse }

	func throwIfHTTPResponseButNotSuccessStatusCode() throws {
		guard let httpURLResponse = http else {
			return
		}

		try httpURLResponse.throwIfNotSuccessStatusCode()
	}
}


extension HTTPURLResponse {
	struct StatusCodeError: LocalizedError {
		let statusCode: Int

		var errorDescription: String {
			HTTPURLResponse.localizedString(forStatusCode: statusCode)
		}
	}

	/**
	`true` if the status code is in `200...299` range.
	*/
	var hasSuccessStatusCode: Bool { (200...299).contains(statusCode) }

	func throwIfNotSuccessStatusCode() throws {
		guard !hasSuccessStatusCode else {
			return
		}

		throw StatusCodeError(statusCode: statusCode)
	}
}


extension URLRequest {
	enum Method: String {
		case get
		case post
		case delete
		case put
		case head
	}

	enum ContentType {
		static let json = "application/json"
	}

	static func json(
		_ method: Method,
		url: URL,
		data: Data? = nil
	) -> Self {
		var request = self.init(url: url)
		request.method = method
		request.addValue(ContentType.json, forHTTPHeaderField: "Accept")
		request.addValue(ContentType.json, forHTTPHeaderField: "Content-Type")

		if let data = data {
			request.httpBody = data
		}

		return request
	}

	static func json(
		_ method: Method,
		url: URL,
		parameters: [String: Any]
	) throws -> Self {
		json(
			method,
			url: url,
			data: try JSONSerialization.data(withJSONObject: parameters, options: [])
		)
	}

	/**
	Strongly-typed version of `httpMethod`.
	*/
	var method: Method {
		get {
			guard let httpMethod = httpMethod else {
				return .get
			}

			return Method(rawValue: httpMethod.lowercased())!
		}
		set {
			httpMethod = newValue.rawValue
		}
	}
}


extension URLSession {
	enum JSONRequestError: Error {
		case nonObject
	}

	/**
	Send a JSON request.

	- Note: This method assumes the response is a JSON object.
	*/
	func json(
		_ method: URLRequest.Method,
		url: URL,
		parameters: [String: Any]
	) async throws -> ([String: Any], URLResponse) {
		let request = try URLRequest.json(method, url: url, parameters: parameters)
		let (data, response) = try await data(for: request)

		try response.throwIfHTTPResponseButNotSuccessStatusCode()

		let json = try JSONSerialization.jsonObject(with: data, options: [])

		guard let dictionary = json as? [String: Any] else {
			throw JSONRequestError.nonObject
		}

		return (dictionary, response)
	}
}


extension NSError {
	/**
	Use this for generic app errors.

	- Note: Prefer using a specific enum-type error whenever possible.

	- Parameter description: The description of the error. This is shown as the first line in error dialogs.
	- Parameter recoverySuggestion: Explain how the user how they can recover from the error. For example, "Try choosing a different directory". This is usually shown as the second line in error dialogs.
	- Parameter userInfo: Metadata to add to the error. Can be a custom key or any of the `NSLocalizedDescriptionKey` keys except `NSLocalizedDescriptionKey` and `NSLocalizedRecoverySuggestionErrorKey`.
	- Parameter domainPostfix: String to append to the `domain` to make it easier to identify the error. The domain is the app's bundle identifier.
	*/
	static func appError(
		_ description: String,
		recoverySuggestion: String? = nil,
		userInfo: [String: Any] = [:],
		domainPostfix: String? = nil
	) -> Self {
		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = description

		if let recoverySuggestion = recoverySuggestion {
			userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
		}

		return .init(
			domain: domainPostfix.map { "\(SSApp.id) - \($0)" } ?? SSApp.id,
			code: 1, // This is what Swift errors end up as.
			userInfo: userInfo
		)
	}
}


enum Bluetooth {
	private final class BluetoothManager: NSObject, CBCentralManagerDelegate {
		private let continuation: CheckedContinuation<Bool, Error>
		private var manager: CBCentralManager?
		private var hasCalled = false

		init(continuation: CheckedContinuation<Bool, Error>) {
			self.continuation = continuation
			super.init()
			self.manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
		}

		private func checkAccess() {
			guard CBCentralManager.authorization != .allowedAlways else {
				return
			}

			let recoverySuggestion = OS.current == .macOS
				? "You can grant access in “System Preferences › Security & Privacy › Bluetooth”."
				: "You can grant access in “Settings › \(SSApp.name)”."

			let error = NSError.appError("No access to Bluetooth.", recoverySuggestion: recoverySuggestion)
			continuation.resume(throwing: error)
			hasCalled = true
		}

		func centralManagerDidUpdateState(_ central: CBCentralManager) {
			defer {
				hasCalled = true
			}

			checkAccess()

			guard !hasCalled else {
				return
			}

			continuation.resume(returning: central.state == .poweredOn)
		}
	}

	/**
	Check whether Bluetooth is turned on.

	- Note: You need to have `NSBluetoothAlwaysUsageDescription` in Info.plist. On macOS, you also need `com.apple.security.device.bluetooth` in your entitlements file.

	- Throws: An error if the app has no access to Bluetooth with a message on how to grant it.
	*/
	static func isOn() async throws -> Bool {
		// Required as otherwise `BluetoothManager` will not be retained long enough.
		var manager: BluetoothManager?

		// Silence Swift compiler warning.
		withExtendedLifetime(manager) {}

		return try await withCheckedThrowingContinuation { continuation in
			manager = BluetoothManager(continuation: continuation)
		}
	}
}


extension Error {
	/**
	The `.localizedDescription` property does not include `.localizedRecoverySuggestion`, so you might miss out on important information. This property includes both.

	Use this property when you have to pass the error to something that will present the error to the user, but only accepts a string. For example, the returned error message in an Siri intent handler.
	*/
	var presentableMessage: String {
		let nsError = self as NSError
		let description = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

		guard
			let recoverySuggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)
		else {
			return description
		}

		return "\(description.ensureSuffix(".")) \(recoverySuggestion.ensureSuffix("."))"
	}
}


extension String {
	func copyToPasteboard() {
		#if canImport(AppKit)
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(self, forType: .string)
		#elseif canImport(UIKit)
		UIPasteboard.general.string = self
		#endif
	}
}


#if canImport(UIKit)
extension UIPasteboard {
	/**
	AppKit polyfill.
	*/
	func clearContents() {
		string = ""
	}
}
#endif


extension View {
	/**
	Embed the view in a `NavigationView`.

	- Note: Modifiers before this apply to the contents and modifiers after apply to the `NavigationView`.
	*/
	@ViewBuilder
	func embedInNavigationView(shouldEmbed: Bool = true) -> some View {
		if shouldEmbed {
			NavigationView {
				self
			}
		} else {
			self
		}
	}

	/**
	Embed the view in a `NavigationView` if the current platform is **not** macOS.

	This can be useful when you want a navigation view in a sheet, as macOS would try to add a sidebar then, which you probably don't want.

	- Note: Modifiers before this apply to the contents and modifiers after apply to the `NavigationView`.
	*/
	@ViewBuilder
	func embedInNavigationViewIfNotMacOS() -> some View {
		#if canImport(AppKit)
		self
		#elseif canImport(UIKit)
		embedInNavigationView()
		#endif
	}
}


extension INIntent {
	/**
	The name of the intent, which is the same as its identifier. For example, `WriteTextIntent`.
	*/
	static var typeName: String {
		// This is safe as the intent identifier is stable.
		String(describing: self)
	}

	/**
	Create a `NSUserActivity` instance based on the name of the intent.

	This can be useful for intent handlers that needs to continue in the main app.

	```
	@MainActor
	final class WriteTextIntentHandler: NSObject, WriteTextIntentHandling {
		func handle(intent: WriteTextIntent) async -> WriteTextIntentResponse {
			.init(code: .continueInApp, userActivity: WriteTextIntent.nsUserActivity)
		}
	}
	```
	*/
	static var nsUserActivity: NSUserActivity {
		// This is safe as the intent identifier is stable.
		.init(activityType: typeName)
	}
}


extension View {
	/**
	Type-safe alternative to `.onContinueUserActivity()` specifically for intents.

	```
	.onContinueIntent(WriteTextIntent.self) { intent, _ in
		text = intent.text
	}
	```
	*/
	func onContinueIntent<T: INIntent>(
		_ intentType: T.Type,
		perform action: @escaping (T, NSUserActivity) -> Void
	) -> some View {
		onContinueUserActivity(intentType.typeName) {
			guard let intent = $0.interaction?.intent as? T else {
				assertionFailure()
				return
			}

			action(intent, $0)
		}
	}
}


extension View {
	/**
	Present a fullscreen cover on iOS and a sheet on macOS.
	*/
	func fullScreenCoverOrSheetIfMacOS<Item, Content>(
		item: Binding<Item?>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping (Item) -> Content
	) -> some View where Item: Identifiable, Content: View {
		#if canImport(AppKit)
		return sheet(item: item, onDismiss: onDismiss, content: content)
		#elseif canImport(UIKit)
		return fullScreenCover(item: item, onDismiss: onDismiss, content: content)
		#endif
	}
}


#if canImport(AppKit)
extension CGEventType {
	/**
	Any event.

	This case is missing from Swift and `kCGAnyInputEventType` is not available in Swift either.
	*/
	static let any = Self(rawValue: ~0)!
}
#endif


enum User {
	#if canImport(AppKit)
	/**
	Th current user's username.

	For example: `sindresorhus`
	*/
	static let username = ProcessInfo.processInfo.userName
	#endif

	#if canImport(AppKit)
	/**
	The current user's name.

	For example: `Sindre Sorhus`
	*/
	static let nameString = ProcessInfo.processInfo.fullUserName
	#elseif canImport(UIKit)
	/**
	The current user's name.

	For example: `Sindre Sorhus`

	- Note: The name may not be available, it may only be the given name, or it may be empty.
	*/
	static let nameString: String = {
		let name = UIDevice.current.name

		if name.hasSuffix("’s iPhone") {
			return name.replacingSuffix("’s iPhone", with: "")
		}

		if name.hasSuffix("’s iPad") {
			return name.replacingSuffix("’s iPad", with: "")
		}

		if name.hasSuffix("’s Apple Watch") {
			return name.replacingSuffix("’s Apple Watch", with: "")
		}

		return ""
	}()
	#endif

	/**
	The current user's name.

	- Note: The name might not be available on iOS.
	*/
	static let name = try? PersonNameComponents(nameString)

	/**
	The current user's language code.

	For example: `en`
	*/
	static var languageCode: String { Locale.current.languageCode ?? "en" }

	/**
	The current user's shell.
	*/
	static let shell: String = {
		guard
			let shell = getpwuid(getuid())?.pointee.pw_shell
		else {
			return "/bin/zsh"
		}

		return String(cString: shell)
	}()

	#if canImport(AppKit)
	/**
	The duration since the user was last active on the computer.
	*/
	static var idleTime: TimeInterval {
		CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .any)
	}
	#endif
}


extension CNContact {
	static var personNameComponentsFetchKeys = [
		CNContactNamePrefixKey,
		CNContactGivenNameKey,
		CNContactMiddleNameKey,
		CNContactFamilyNameKey,
		CNContactNameSuffixKey,
		CNContactNicknameKey,
		CNContactPhoneticGivenNameKey,
		CNContactPhoneticMiddleNameKey,
		CNContactPhoneticFamilyNameKey
	] as [CNKeyDescriptor]

	/**
	Convert a `CNContact` to a `PersonNameComponents`.

	- Important: Ensure you have fetched the needed keys. You can use `CNContact.personNameComponentsFetchKeys` to get the keys.
	*/
	var toPersonNameComponents: PersonNameComponents {
		.init(
			namePrefix: isKeyAvailable(CNContactNamePrefixKey) ? namePrefix : nil,
			givenName: isKeyAvailable(CNContactGivenNameKey) ? givenName : nil,
			middleName: isKeyAvailable(CNContactMiddleNameKey) ? middleName : nil,
			familyName: isKeyAvailable(CNContactFamilyNameKey) ? familyName : nil,
			nameSuffix: isKeyAvailable(CNContactNameSuffixKey) ? nameSuffix : nil,
			nickname: isKeyAvailable(CNContactNicknameKey) ? nickname : nil,
			phoneticRepresentation: .init(
				givenName: isKeyAvailable(CNContactPhoneticGivenNameKey) ? phoneticGivenName : nil,
				middleName: isKeyAvailable(CNContactPhoneticMiddleNameKey) ? phoneticMiddleName : nil,
				familyName: isKeyAvailable(CNContactPhoneticFamilyNameKey) ? phoneticFamilyName : nil
			)
		)
	}
}


extension CNContactStore {
	private var legacyMeIdentifier: Int? {
		guard let containers = try? containers(matching: nil) else {
			return nil
		}

		return containers
			.lazy
			.compactMap {
				guard let identifier = $0.value(forKey: "meIdentifier") as? String else {
					return nil
				}

				return Int(identifier)
			}
			.first
	}

	/**
	The “me” contact identifier, if any.
	*/
	func meContactIdentifier() -> String? {
		let legacyMeIdentifier = legacyMeIdentifier
		var meIdentifier: String?

		try? enumerateContacts(with: .init(keysToFetch: [])) { contact, stop in
			guard let legacyIdentifier = contact.value(forKey: "iOSLegacyIdentifier") as? Int else {
				return
			}

			if legacyIdentifier == legacyMeIdentifier {
				meIdentifier = contact.identifier
				stop.pointee = true
			}
		}

		return meIdentifier
	}

	/**
	The “me” contact, if any, as person name components.
	*/
	func meContactPerson() -> PersonNameComponents? {
		guard
			let identifier = meContactIdentifier(),
			let contact = try? unifiedContact(withIdentifier: identifier, keysToFetch: CNContact.personNameComponentsFetchKeys)
		else {
			return nil
		}

		return contact.toPersonNameComponents
	}
}


extension View {
	/**
	Conditionally modify the view. For example, apply modifiers, wrap the view, etc.

	```
	Text("Foo")
		.padding()
		.if(someCondition) {
			$0.foregroundColor(.pink)
		}
	```

	```
	VStack() {
		Text("Line 1")
		Text("Line 2")
	}
		.if(someCondition) { content in
			ScrollView(.vertical) { content }
		}
	```
	*/
	@ViewBuilder
	func `if`<Content: View>(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> Content
	) -> some View {
		if condition() {
			modify(self)
		} else {
			self
		}
	}

	/**
	This overload makes it possible to preserve the type. For example, doing an `if` in a chain of `Text`-only modifiers.

	```
	Text("🦄")
		.if(isOn) {
			$0.fontWeight(.bold)
		}
		.kerning(10)
	```
	*/
	func `if`(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> Self
	) -> Self {
		condition() ? modify(self) : self
	}
}


extension View {
	/**
	Conditionally modify the view. For example, apply modifiers, wrap the view, etc.
	*/
	@ViewBuilder
	func `if`<IfContent: View, ElseContent: View>(
		_ condition: @autoclosure () -> Bool,
		if modifyIf: (Self) -> IfContent,
		else modifyElse: (Self) -> ElseContent
	) -> some View {
		if condition() {
			modifyIf(self)
		} else {
			modifyElse(self)
		}
	}

	/**
	Conditionally modify the view. For example, apply modifiers, wrap the view, etc.

	This overload makes it possible to preserve the type. For example, doing an `if` in a chain of `Text`-only modifiers.
	*/
	func `if`(
		_ condition: @autoclosure () -> Bool,
		if modifyIf: (Self) -> Self,
		else modifyElse: (Self) -> Self
	) -> Self {
		condition() ? modifyIf(self) : modifyElse(self)
	}
}

extension Font {
	/**
	Conditionally modify the font. For example, apply modifiers.

	```
	Text("Foo")
		.font(
			Font.system(size: 10, weight: .regular)
				.if(someBool) {
					$0.monospacedDigit()
				}
		)
	```
	*/
	func `if`(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> Self
	) -> Self {
		condition() ? modify(self) : self
	}
}


#if canImport(UIKit)
extension UIFont.TextStyle {
	var font: UIFont { .preferredFont(forTextStyle: self) }

	var weight: UIFont.Weight { font.weight }
}

extension UIFont.Weight {
	var toSwiftUIFontWeight: Font.Weight {
		switch self {
		case .ultraLight:
			return .ultraLight
		case .thin:
			return .thin
		case .light:
			return .light
		case .regular:
			return .regular
		case .medium:
			return .medium
		case .semibold:
			return .semibold
		case .bold:
			return .bold
		case .heavy:
			return .heavy
		case .black:
			return .black
		default:
			return .regular
		}
	}
}

extension Font.TextStyle {
	var weight: Font.Weight { toUIFontTextStyle.weight.toSwiftUIFontWeight }

	var toUIFontTextStyle: UIFont.TextStyle {
		switch self {
		case .largeTitle:
			return .largeTitle
		case .title:
			return .title1
		case .title2:
			return .title2
		case .title3:
			return .title3
		case .headline:
			return .headline
		case .body:
			return .body
		case .callout:
			return .callout
		case .subheadline:
			return .subheadline
		case .footnote:
			return .footnote
		case .caption:
			return .caption1
		case .caption2:
			return .caption2
		@unknown default:
			return .body
		}
	}
}

extension UIFont {
	var traits: [UIFontDescriptor.TraitKey: Any] {
		fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any] ?? [:]
	}

	var weight: Weight { traits[.weight] as? Weight ?? .regular }
}
#endif

extension Font {
	/**
	Specifies a system font where the given size scales relative to the given text style.

	It respects the weight of the text style if no `weight` is specified.

	On macOS, there is no Dynamic Type, so the `relativeTo` parameter has no effect.
	*/
	static func system(
		size: Double,
		relativeTo textStyle: TextStyle,
		weight: Weight? = nil,
		design: Design = .default
	) -> Self {
		#if canImport(AppKit)
		return .system(size: size, weight: weight ?? .regular, design: design)
		#elseif canImport(UIKit)
		let style = textStyle.toUIFontTextStyle

		return .system(
			size: style.metrics.scaledValue(for: size),
			weight: weight ?? style.weight.toSwiftUIFontWeight,
			design: design
		)
		#endif
	}
}

extension Font {
	/**
	A font with a large body text style.
	*/
	static var largeBody: Self {
		.system(size: OS.current == .macOS ? 16 : 20, relativeTo: .body)
	}
}


extension StringProtocol {
	/**
	Removes characters without a display width, often referred to as invisible or non-printable characters.

	This does not include normal whitespace characters.

	```
	let x = "\u{202A}foo "

	print(x.count)
	//=> 5

	print(x.removingCharactersWithoutDisplayWidth().count)
	//=> 4
	```
	*/
	func removingCharactersWithoutDisplayWidth() -> String {
		replacingOccurrences(of: #"[\p{Control}\p{Format}\p{Nonspacing_Mark}\p{Enclosing_Mark}\p{Line_Separator}\p{Paragraph_Separator}\p{Private_Use}\p{Unassigned}]"#, with: "", options: .regularExpression)
	}
}


extension Sequence {
	/**
	Sort a sequence by a key path.

	```
	["ab", "a", "abc"].sorted(by: \.count)
	//=> ["a", "ab", "abc"]
	```
	*/
	public func sorted<Value: Comparable>(
		by keyPath: KeyPath<Element, Value>,
		order: SortOrder = .forward
	) -> [Element] {
		switch order {
		case .forward:
			return sorted { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
		case .reverse:
			return sorted { $0[keyPath: keyPath] > $1[keyPath: keyPath] }
		}
	}
}


extension Sequence {
	/**
	Convert a sequence to a dictionary by mapping over the values and using the returned key as the key and the current sequence element as value.

	If the the returned key is `nil`, the element is skipped.

	```
	[1, 2, 3].toDictionary { $0 }
	//=> [1: 1, 2: 2, 3: 3]

	[1, 2, 3].toDictionary(withKey: \.self)
	//=> [1: 1, 2: 2, 3: 3]
	```
	*/
	func toDictionaryCompact<Key: Hashable>(withKey pickKey: (Element) -> Key?) -> [Key: Element] {
		var dictionary = [Key: Element]()

		for element in self {
			guard let key = pickKey(element) else {
				continue
			}

			dictionary[key] = element
		}

		return dictionary
	}
}


extension Locale {
	static let all = availableIdentifiers.map { Self(identifier: $0) }

	/**
	A dictionary with available currency codes as keys and their locale as value.
	*/
	static let currencyCodesWithLocale = all
		 .removingDuplicates(by: \.currencyCode)
		 .toDictionaryCompact(withKey: \.currencyCode)

	/**
	An array of tuples with currency code and its localized currency name and localized region name.
	*/
	static let currencyCodesWithLocalizedNameAndRegionName: [(currencyCode: String, localizedCurrencyName: String, localizedRegionName: String)] = currencyCodesWithLocale
		 .compactMap { currencyCode, locale in
			 guard
				let regionCode = locale.regionCode,
				let localizedCurrencyName = locale.localizedString(forCurrencyCode: currencyCode),
				let localizedRegionName = locale.localizedString(forRegionCode: regionCode)
			 else {
				 return nil
			 }

			 return (currencyCode, localizedCurrencyName, localizedRegionName)
		 }
		 .sorted(by: \.currencyCode)
}


extension Locale {
	var localizedName: String { Self.current.localizedString(forIdentifier: identifier) ?? identifier }
}


#if canImport(AppKit)
extension NSWorkspace {
	/**
	Running GUI apps. Excludes menu bar apps and daemons.
	*/
	var runningGUIApps: [NSRunningApplication] {
		runningApplications.filter { $0.activationPolicy == .regular }
	}
}
#endif


struct SystemSound: Hashable, Identifiable {
	let id: SystemSoundID

	func play() async {
		await withCheckedContinuation { continuation in
			AudioServicesPlaySystemSoundWithCompletion(id) {
				continuation.resume()
			}
		}
	}
}

extension SystemSound {
	/**
	Create a system sound from a URL pointing to an audio file.
	*/
	init?(_ url: URL) {
		var id: SystemSoundID = 0
		guard AudioServicesCreateSystemSoundID(url as NSURL, &id) == kAudioServicesNoError else {
			return nil
		}

		self.id = id
	}

	/**
	Create a system sound from a Base64-encoded audio file.
	*/
	init?(base64EncodedFile: String, ofType contentType: UTType) {
		guard
			let url = try? Data(base64Encoded: base64EncodedFile)?
				.writeToUniqueTemporaryFile(contentType: contentType)
		else {
			return nil
		}

		self.init(url)
	}
}

extension Device {
	private static let silentAudio: SystemSound? = {
		// Smallest valid MP3 file.
		let audio = "/+MYxAAAAANIAAAAAExBTUUzLjk4LjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

		return SystemSound(base64EncodedFile: audio, ofType: .mp3)
	}()

	/**
	Whether the silent switch on the device is enabled.
	*/
	@available(macOS, unavailable)
	static var isSilentModeEnabled: Bool {
		get async {
			guard let silentAudio = silentAudio else {
				assertionFailure()
				return false
			}

			// When silent mode is enabled, the system skips playing the audio file and the function takes less than a millisecond to execute. We check for this to determine whether silent mode is enabled.

			let startTime = CACurrentMediaTime()
			await silentAudio.play()
			let duration = CACurrentMediaTime() - startTime
			return duration < 0.01
		}
	}
}


#if canImport(UIKit)
extension Device {
	enum HapticFeedback {
		case success
		case warning
		case error
		case selection
		case soft
		case light
		case medium
		case heavy
		case rigid
		case legacy

		fileprivate func generate() {
			switch self {
			case .success:
				UINotificationFeedbackGenerator().notificationOccurred(.success)
			case .warning:
				UINotificationFeedbackGenerator().notificationOccurred(.warning)
			case .error:
				UINotificationFeedbackGenerator().notificationOccurred(.error)
			case .selection:
				UISelectionFeedbackGenerator().selectionChanged()
			case .soft:
				UIImpactFeedbackGenerator(style: .soft).impactOccurred()
			case .light:
				UIImpactFeedbackGenerator(style: .light).impactOccurred()
			case .medium:
				UIImpactFeedbackGenerator(style: .medium).impactOccurred()
			case .heavy:
				UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
			case .rigid:
				UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
			case .legacy:
				AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate, nil)
			}
		}
	}

	static func hapticFeedback(_ type: HapticFeedback) {
		type.generate()
	}
}
#endif


#if canImport(AppKit)
extension NSImage {
	var inImage: INImage {
		// `tiffRepresentation` is very unlikely to fail, so we just fall back to an empty image.
		INImage(imageData: tiffRepresentation ?? Data())
	}
}
#elseif canImport(UIKit) && canImport(IntentsUI)
extension UIImage {
	/**
	Convert an `UIImage` to `INImage`.

	- Important: If you're using this in an intent handler extension, don't forget to manually add the `IntentsUI` framework.
	*/
	var inImage: INImage { INImage(uiImage: self) }
}
#endif
