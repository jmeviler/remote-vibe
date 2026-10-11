import Foundation

// Chinese source strings are the fallback for standalone tools without a resource bundle.
func L(_ key: String, _ arguments: String...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
}
