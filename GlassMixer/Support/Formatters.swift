import Foundation

enum Formatters {
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
