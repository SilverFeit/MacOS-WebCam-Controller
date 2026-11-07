import Foundation

/// Translates short natural-language or keyword look descriptions (English & Spanish) into relative or absolute
/// UVC hardware adjustments (`brightness`, `contrast`, `saturation`, `sharpness`, `whiteBalanceTemperature`, `backlight`, `zoom`).
public struct LookAdjustment: Equatable, Sendable {
    public enum TargetControl: String, Sendable {
        case brightness
        case contrast
        case saturation
        case sharpness
        case whiteBalanceTemperature = "white_balance_temp"
        case backlight = "backlight_compensation"
        case zoom
    }

    public enum Operation: Equatable, Sendable {
        /// Shifts the control by a fraction of its hardware range (e.g. `+0.12` = +12% of `(max - min)`).
        case relativeFraction(Double)
        /// Sets the control to a normalized fraction `0.0 ... 1.0` between `minimum` and `maximum`.
        case normalized(Double)
        /// Resets all image-processing controls to their hardware defaults.
        case resetImage
        /// Resets all optical framing (Zoom, Pan, Tilt, Roll) to their hardware defaults.
        case resetView
    }

    public struct Step: Equatable, Sendable {
        public let control: TargetControl?
        public let operation: Operation
        public let label: String

        public init(control: TargetControl?, operation: Operation, label: String) {
            self.control = control
            self.operation = operation
            self.label = label
        }
    }

    /// Parses a comma- or conjunction-separated phrase (e.g. `"warmer, more contrast"`, `"mas calido y mas brillo"`,
    /// `"black and white"`, `"natural"`) into hardware adjustment steps.
    public static func parse(_ phrase: String) -> [Step] {
        let normalized = phrase
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "black and white", with: "monochrome")
            .replacingOccurrences(of: "black & white", with: "monochrome")
            .replacingOccurrences(of: "blanco y negro", with: "monochrome")
            .replacingOccurrences(of: " & ", with: ",")
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " y ", with: ",")
            .replacingOccurrences(of: ";", with: ",")

        let clauses = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var steps: [Step] = []
        for clause in (clauses.isEmpty ? [normalized.trimmingCharacters(in: .whitespacesAndNewlines)] : clauses) {
            guard !clause.isEmpty else { continue }
            let scale: Double = (clause.contains("much") || clause.contains("very") || clause.contains("way") || clause.contains("lot") || clause.contains("mucho") || clause.contains("muy")) ? 2.0
                : ((clause.contains("slight") || clause.contains("little") || clause.contains("bit") || clause.contains("poco") || clause.contains("liger")) ? 0.5 : 1.0)

            if clause == "natural" || clause == "normal" || clause == "default" || clause == "reset" || clause == "reset image" || clause == "restablecer" {
                steps.append(Step(control: nil, operation: .resetImage, label: "natural defaults"))
                continue
            }
            if clause == "reset view" || clause == "center" || clause == "centrar" || clause == "wide" {
                steps.append(Step(control: nil, operation: .resetView, label: "reset view"))
                continue
            }
            if clause.contains("black and white") || clause.contains("black & white") || clause == "bw" || clause == "b&w" || clause.contains("monochrome") || clause.contains("grayscale") || clause.contains("blanco y negro") || clause.contains("gris") {
                steps.append(Step(control: .saturation, operation: .normalized(0.0), label: "monochrome"))
                continue
            }
            if clause.contains("warm") || clause.contains("calid") || clause.contains("golden") || clause.contains("amarill") {
                let sign = (clause.contains("less") || clause.contains("menos")) ? -1.0 : 1.0
                steps.append(Step(control: .whiteBalanceTemperature, operation: .relativeFraction(0.14 * scale * sign), label: sign > 0 ? "warmer" : "cooler"))
                continue
            }
            if clause.contains("cool") || clause.contains("cold") || clause.contains("frio") || clause.contains("fria") || clause.contains("blue") || clause.contains("azul") {
                let sign = (clause.contains("less") || clause.contains("menos")) ? 1.0 : -1.0
                steps.append(Step(control: .whiteBalanceTemperature, operation: .relativeFraction(0.14 * scale * sign), label: sign < 0 ? "cooler" : "warmer"))
                continue
            }
            if clause.contains("bright") || clause.contains("light") || clause.contains("brill") || clause.contains("clar") {
                let sign = (clause.contains("less") || clause.contains("menos") || clause.contains("dim") || clause.contains("dark")) ? -1.0 : 1.0
                steps.append(Step(control: .brightness, operation: .relativeFraction(0.12 * scale * sign), label: sign > 0 ? "brighter" : "darker"))
                continue
            }
            if clause.contains("dark") || clause.contains("dim") || clause.contains("oscur") || clause.contains("low key") {
                steps.append(Step(control: .brightness, operation: .relativeFraction(-0.12 * scale), label: "darker"))
                continue
            }
            if clause.contains("contrast") || clause.contains("punch") || clause.contains("pop") {
                let sign = (clause.contains("less") || clause.contains("menos") || clause.contains("flat") || clause.contains("soft")) ? -1.0 : 1.0
                steps.append(Step(control: .contrast, operation: .relativeFraction(0.12 * scale * sign), label: sign > 0 ? "more contrast" : "less contrast"))
                continue
            }
            if clause.contains("flat") || clause.contains("matte") || clause.contains("plan") {
                steps.append(Step(control: .contrast, operation: .relativeFraction(-0.12 * scale), label: "less contrast"))
                continue
            }
            if clause.contains("vivid") || clause.contains("vibrant") || clause.contains("saturat") || clause.contains("color") || clause.contains("vivo") {
                let sign = (clause.contains("less") || clause.contains("menos") || clause.contains("mute") || clause.contains("desatur")) ? -1.0 : 1.0
                steps.append(Step(control: .saturation, operation: .relativeFraction(0.15 * scale * sign), label: sign > 0 ? "more saturation" : "less saturation"))
                continue
            }
            if clause.contains("mute") || clause.contains("desatur") || clause.contains("pale") || clause.contains("apagad") {
                steps.append(Step(control: .saturation, operation: .relativeFraction(-0.15 * scale), label: "muted saturation"))
                continue
            }
            if clause.contains("sharp") || clause.contains("crisp") || clause.contains("nitid") || clause.contains("detail") {
                let sign = (clause.contains("less") || clause.contains("menos") || clause.contains("soft")) ? -1.0 : 1.0
                steps.append(Step(control: .sharpness, operation: .relativeFraction(0.16 * scale * sign), label: sign > 0 ? "sharper" : "softer"))
                continue
            }
            if clause.contains("soft") || clause.contains("smooth") || clause.contains("suave") {
                steps.append(Step(control: .sharpness, operation: .relativeFraction(-0.16 * scale), label: "softer"))
                continue
            }
            if clause.contains("backlight") || clause.contains("contraluz") || clause.contains("hdr") {
                let on = !(clause.contains("off") || clause.contains("no ") || clause.contains("apag"))
                steps.append(Step(control: .backlight, operation: .normalized(on ? 1.0 : 0.0), label: on ? "backlight on" : "backlight off"))
                continue
            }
            if clause.contains("zoom in") || clause.contains("closer") || clause.contains("acerc") {
                steps.append(Step(control: .zoom, operation: .relativeFraction(0.15 * scale), label: "zoom in"))
                continue
            }
            if clause.contains("zoom out") || clause.contains("wider") || clause.contains("alej") {
                steps.append(Step(control: .zoom, operation: .relativeFraction(-0.15 * scale), label: "zoom out"))
                continue
            }
        }
        return steps
    }
}
