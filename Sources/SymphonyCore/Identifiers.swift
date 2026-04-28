import Foundation

public struct ProjectID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }

    public init() {
        rawValue = UUID().uuidString
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct TaskID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }

    public init() {
        rawValue = UUID().uuidString
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct RunID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }

    public init() {
        rawValue = UUID().uuidString
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AgentSessionID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }

    public init() {
        rawValue = UUID().uuidString
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
