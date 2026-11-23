import Foundation

/// Pixel sample aspect ratio (`width : height`), e.g. 1:1 (square), 32:27 (NTSC 16:9), 8:9 (NTSC 4:3).
public struct SampleAspectRatio: Codable, Hashable, Sendable {
    public let numerator: Int
    public let denominator: Int

    public static let square = SampleAspectRatio(numerator: 1, denominator: 1)

    public init(numerator: Int, denominator: Int) {
        guard numerator > 0, denominator > 0 else {
            self.numerator = 1
            self.denominator = 1
            return
        }
        let divisor = Self.gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    /// Parses ffprobe SAR strings such as `"1:1"`, `"32:27"`, `"64:45"`. Returns `nil` for `"N/A"`, `"0:1"`, or invalid strings.
    public static func parse(_ raw: String?) -> SampleAspectRatio? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "N/A" else { return nil }
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let num = Int(parts[0]),
              let den = Int(parts[1]),
              num > 0, den > 0 else {
            return nil
        }
        return SampleAspectRatio(numerator: num, denominator: den)
    }

    public var isSquare: Bool { numerator == denominator }
    public var ratio: Double { Double(numerator) / Double(denominator) }
    public var formatted: String { "\(numerator):\(denominator)" }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let r = x % y
            x = y
            y = r
        }
        return max(1, x)
    }
}

/// Active picture bounding box reported by `ffmpeg cropdetect` (`crop=w:h:x:y`).
public struct CropRect: Codable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isValid: Bool { width > 0 && height > 0 && x >= 0 && y >= 0 }
}

/// Matroska edge offsets (`pixel-crop-left/right/top/bottom`) relative to encoded PixelWidth × PixelHeight.
public struct CropInsets: Codable, Hashable, Sendable {
    public var left: Int
    public var right: Int
    public var top: Int
    public var bottom: Int

    public static let zero = CropInsets(left: 0, right: 0, top: 0, bottom: 0)

    public init(left: Int, right: Int, top: Int, bottom: Int) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public var isZero: Bool {
        left == 0 && right == 0 && top == 0 && bottom == 0
    }

    public func croppedWidth(for frameWidth: Int) -> Int {
        max(0, frameWidth - left - right)
    }

    public func croppedHeight(for frameHeight: Int) -> Int {
        max(0, frameHeight - top - bottom)
    }

    public var summary: String {
        "L \(left) · R \(right) · T \(top) · B \(bottom)"
    }
}

/// Target Matroska display dimensions (`display-width`, `display-height`, `display-unit`).
public struct DisplayDimensions: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// Matroska DisplayUnit: 0 = pixels.
    public let unit: Int

    public init(width: Int, height: Int, unit: Int = 0) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.unit = unit
    }

    public var aspectRatio: Double {
        Double(width) / Double(height)
    }

    public var formattedAspectRatio: String {
        String(format: "%.2f:1", aspectRatio)
    }

    public var formattedDimensions: String {
        "\(width)×\(height)"
    }
}

/// Raw EBML Video track header fields read directly from Matroska track v1.
/// Optional fields distinguish absent elements (restored with `--delete`) from explicit values (`--set`).
public struct MatroskaVideoHeader: Codable, Hashable, Sendable {
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var pixelCropLeft: Int?
    public var pixelCropRight: Int?
    public var pixelCropTop: Int?
    public var pixelCropBottom: Int?
    public var displayWidth: Int?
    public var displayHeight: Int?
    public var displayUnit: Int?

    public init(
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        pixelCropLeft: Int? = nil,
        pixelCropRight: Int? = nil,
        pixelCropTop: Int? = nil,
        pixelCropBottom: Int? = nil,
        displayWidth: Int? = nil,
        displayHeight: Int? = nil,
        displayUnit: Int? = nil
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pixelCropLeft = pixelCropLeft
        self.pixelCropRight = pixelCropRight
        self.pixelCropTop = pixelCropTop
        self.pixelCropBottom = pixelCropBottom
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.displayUnit = displayUnit
    }

    public var effectiveCropInsets: CropInsets {
        CropInsets(
            left: pixelCropLeft ?? 0,
            right: pixelCropRight ?? 0,
            top: pixelCropTop ?? 0,
            bottom: pixelCropBottom ?? 0
        )
    }

    public var hasAnyCropElement: Bool {
        pixelCropLeft != nil || pixelCropRight != nil || pixelCropTop != nil || pixelCropBottom != nil
    }

    public var hasNonZeroCrop: Bool {
        !effectiveCropInsets.isZero
    }
}
