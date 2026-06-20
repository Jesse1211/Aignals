import Foundation

public enum VerbMapper {
    public static func verb(forTool tool: String) -> String {
        switch tool {
        case "Edit", "Write": return "Editing"
        case "Bash":          return "Running"
        case "Read":          return "Reading"
        case "Glob", "Grep":  return "Searching"
        default:
            guard let first = tool.first else { return "" }
            return String(first).uppercased() + tool.dropFirst().lowercased()
        }
    }
}
