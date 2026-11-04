import SwiftUI
import UVCCore

// MARK: - Classic Webcam Settings Panel Diamond & Hardware Icons

public struct DiamondBadgeIcon: View {
    public enum Style {
        case lowContrast
        case highContrast
        case hueLeft
        case hueRight
        case saturationLow
        case saturationHigh
        case sharpnessSoft
        case sharpnessCrisp
        case gammaLow
        case gammaHigh
        case kelvinCool
        case kelvinWarm
    }

    let style: Style

    public init(_ style: Style) {
        self.style = style
    }

    public var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r = min(w, h) * 0.44

            var diamond = Path()
            diamond.move(to: CGPoint(x: cx, y: cy - r))
            diamond.addLine(to: CGPoint(x: cx + r, y: cy))
            diamond.addLine(to: CGPoint(x: cx, y: cy + r))
            diamond.addLine(to: CGPoint(x: cx - r, y: cy))
            diamond.closeSubpath()

            switch style {
            case .lowContrast:
                ctx.fill(diamond, with: .color(.gray.opacity(0.65)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.55)), lineWidth: 1.1)

            case .highContrast:
                var leftHalf = Path()
                leftHalf.move(to: CGPoint(x: cx, y: cy - r))
                leftHalf.addLine(to: CGPoint(x: cx, y: cy + r))
                leftHalf.addLine(to: CGPoint(x: cx - r, y: cy))
                leftHalf.closeSubpath()

                var rightHalf = Path()
                rightHalf.move(to: CGPoint(x: cx, y: cy - r))
                rightHalf.addLine(to: CGPoint(x: cx + r, y: cy))
                rightHalf.addLine(to: CGPoint(x: cx, y: cy + r))
                rightHalf.closeSubpath()

                ctx.fill(leftHalf, with: .color(.white))
                ctx.fill(rightHalf, with: .color(.black.opacity(0.85)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.75)), lineWidth: 1.1)

            case .hueLeft:
                ctx.fill(diamond, with: .color(Color(red: 0.35, green: 0.85, blue: 0.42)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.55)), lineWidth: 1.0)

            case .hueRight:
                ctx.fill(diamond, with: .color(Color(red: 0.88, green: 0.36, blue: 0.92)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.55)), lineWidth: 1.0)

            case .saturationLow:
                ctx.fill(diamond, with: .color(.gray.opacity(0.35)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.5)), lineWidth: 1.0)

            case .saturationHigh:
                let grad = Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple])
                ctx.fill(
                    diamond,
                    with: .linearGradient(
                        grad,
                        startPoint: CGPoint(x: cx - r, y: cy - r),
                        endPoint: CGPoint(x: cx + r, y: cy + r)
                    )
                )
                ctx.stroke(diamond, with: .color(.primary.opacity(0.55)), lineWidth: 1.0)

            case .sharpnessSoft:
                ctx.fill(diamond, with: .color(.gray.opacity(0.18)))
                ctx.stroke(
                    diamond,
                    with: .color(.secondary.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [2, 1.5])
                )

            case .sharpnessCrisp:
                ctx.fill(diamond, with: .color(.clear))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.9)), lineWidth: 1.6)

            case .gammaLow:
                ctx.fill(diamond, with: .color(.black.opacity(0.75)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.65)), lineWidth: 1.1)

            case .gammaHigh:
                ctx.fill(diamond, with: .color(.white.opacity(0.9)))
                ctx.stroke(diamond, with: .color(.primary.opacity(0.75)), lineWidth: 1.1)

            case .kelvinCool:
                ctx.fill(diamond, with: .color(Color(red: 0.58, green: 0.88, blue: 0.98)))
                ctx.stroke(diamond, with: .color(.cyan.opacity(0.8)), lineWidth: 1.0)

            case .kelvinWarm:
                ctx.fill(diamond, with: .color(Color(red: 0.98, green: 0.88, blue: 0.45)))
                ctx.stroke(diamond, with: .color(.orange.opacity(0.75)), lineWidth: 1.0)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Punctual Hardware Rollback Button (Placed to the Right of Icons & Left of Values)

public struct RollbackIconButton: View {
    let isEnabled: Bool
    let isModified: Bool
    let helpText: String
    let action: () -> Void

    public init(
        isEnabled: Bool,
        isModified: Bool,
        helpText: String = "Reset to factory default",
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.isModified = isModified
        self.helpText = helpText
        self.action = action
    }

    public var body: some View {
        Button {
            if isEnabled {
                action()
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10.5, weight: isModified && isEnabled ? .bold : .medium))
                .foregroundStyle(
                    !isEnabled
                    ? Color.secondary.opacity(0.28)
                    : (isModified ? Color.accentColor : Color.secondary.opacity(0.62))
                )
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isModified && isEnabled ? Color.accentColor.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
    }
}

// MARK: - Classic Panel Slider Row (Matches Uploaded Screenshot + Rollback Icon & Live Numeric Readout)

public struct PanelSliderRow<LeftIcon: View, RightIcon: View>: View {
    let label: String
    let labelWidth: CGFloat
    let state: NumericRangeControlState
    let isLockedByAuto: Bool
    let logarithmicScale: Bool
    let formattedValue: String?
    let leftIcon: LeftIcon
    let rightIcon: RightIcon
    let onChange: (Int) -> Void

    public init(
        label: String,
        labelWidth: CGFloat = 104,
        state: NumericRangeControlState,
        isLockedByAuto: Bool = false,
        logarithmicScale: Bool = false,
        formattedValue: String? = nil,
        @ViewBuilder leftIcon: () -> LeftIcon,
        @ViewBuilder rightIcon: () -> RightIcon,
        onChange: @escaping (Int) -> Void
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.state = state
        self.isLockedByAuto = isLockedByAuto
        self.logarithmicScale = logarithmicScale
        self.formattedValue = formattedValue
        self.leftIcon = leftIcon()
        self.rightIcon = rightIcon()
        self.onChange = onChange
    }

    private var isInteractive: Bool {
        state.isSupported && state.canSet && !isLockedByAuto && state.maximum > state.minimum
    }

    private var useLogStops: Bool {
        logarithmicScale && state.isSupported && state.minimum >= 1 && state.maximum > state.minimum
    }

    private var sliderMin: Double {
        guard state.isSupported && state.maximum > state.minimum else { return 0 }
        return useLogStops ? Foundation.log2(Double(max(1, state.minimum))) : Double(state.minimum)
    }

    private var sliderMax: Double {
        guard state.isSupported && state.maximum > state.minimum else { return 100 }
        return useLogStops ? Foundation.log2(Double(max(2, state.maximum))) : Double(state.maximum)
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: {
                guard state.isSupported else { return 0 }
                let clamped = min(max(state.current, state.minimum), max(state.minimum + 1, state.maximum))
                return useLogStops ? Foundation.log2(Double(max(1, clamped))) : Double(clamped)
            },
            set: { newVal in
                if useLogStops {
                    let raw = Int(Foundation.pow(2.0, newVal).rounded())
                    onChange(state.clampedAndSnapped(raw))
                } else {
                    onChange(Int(newVal.rounded()))
                }
            }
        )
    }

    public var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(state.isSupported ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: labelWidth, alignment: .trailing)
                    .lineLimit(1)
            }

            leftIcon
                .frame(width: 16, height: 16)
                .opacity(isInteractive ? 0.9 : 0.35)

            Slider(value: sliderBinding, in: sliderMin...sliderMax)
                .controlSize(.small)
                .disabled(!isInteractive)

            rightIcon
                .frame(width: 16, height: 16)
                .opacity(isInteractive ? 0.9 : 0.35)

            RollbackIconButton(
                isEnabled: isInteractive,
                isModified: state.isSupported && state.current != state.defaultValue,
                helpText: state.isSupported
                    ? "Rollback to default (\(state.defaultValue)) · Range: \(state.minimum)...\(state.maximum)"
                    : "Not supported by this USB camera hardware"
            ) {
                onChange(state.defaultValue)
            }

            Text(state.isSupported ? (formattedValue ?? "\(state.current)") : "N/A")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    !state.isSupported ? Color.secondary.opacity(0.4) :
                    (state.current == state.defaultValue ? Color.secondary : Color.accentColor)
                )
                .frame(minWidth: 42, alignment: .trailing)
                .help(
                    state.isSupported
                    ? "Current: \(state.current) (Default: \(state.defaultValue), Range: \(state.minimum)...\(state.maximum))"
                    : "Not supported by this USB camera hardware"
                )
        }
    }
}

// MARK: - Segmented Button Bar (Supports Per-Option Hardware Enablement, Matching Screenshot!)

public struct SegmentedOptionItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let isEnabled: Bool

    public init(id: ID, title: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
    }
}

public struct HardwareSegmentedBar<ID: Hashable>: View {
    let options: [SegmentedOptionItem<ID>]
    let selectedID: ID?
    let isControlSupported: Bool
    let compact: Bool
    let onSelect: (ID) -> Void

    public init(
        options: [SegmentedOptionItem<ID>],
        selectedID: ID?,
        isControlSupported: Bool = true,
        compact: Bool = false,
        onSelect: @escaping (ID) -> Void
    ) {
        self.options = options
        self.selectedID = selectedID
        self.isControlSupported = isControlSupported
        self.compact = compact
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, item in
                let isSelected = isControlSupported && (selectedID == item.id)
                let enabled = isControlSupported && item.isEnabled

                Button {
                    if enabled {
                        onSelect(item.id)
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: compact ? 10.5 : 11.5, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 3.5 : 4.5)
                        .padding(.horizontal, 4)
                        .background(
                            isSelected
                            ? Color.accentColor.opacity(0.88)
                            : Color(nsColor: .controlBackgroundColor).opacity(enabled ? 0.9 : 0.45)
                        )
                        .foregroundStyle(
                            isSelected
                            ? Color.white
                            : (enabled ? Color.primary : Color.secondary.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!enabled)

                if index < options.count - 1 {
                    Divider()
                        .frame(height: compact ? 18 : 22)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Panel Section Box (Matches Classic macOS GroupBox Styling in Screenshot)

public struct PanelGroupBox<HeaderTrailing: View, Content: View>: View {
    let title: String?
    let headerTrailing: HeaderTrailing
    let content: Content

    public init(
        _ title: String? = nil,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title, !title.isEmpty {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(.leading, 2)
                    Spacer()
                    headerTrailing
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
    }
}

extension PanelGroupBox where HeaderTrailing == EmptyView {
    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, headerTrailing: { EmptyView() }, content: content)
    }
}
