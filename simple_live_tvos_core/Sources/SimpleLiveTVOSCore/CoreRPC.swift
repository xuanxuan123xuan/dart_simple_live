import Foundation

public struct CoreRPCError: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String
    public let statusCode: Int?

    public init(kind: String, message: String, statusCode: Int? = nil) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
    }
}

public struct CoreRPCRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let method: String
    public let payload: [String: JSONValue]

    public init(requestId: String, method: String, payload: [String: JSONValue] = [:]) {
        self.requestId = requestId
        self.method = method
        self.payload = payload
    }
}

public struct CoreRPCResponse: Codable, Equatable, Sendable {
    public let requestId: String
    public let ok: Bool
    public let data: JSONValue?
    public let error: CoreRPCError?

    public init(requestId: String, ok: Bool, data: JSONValue? = nil, error: CoreRPCError? = nil) {
        self.requestId = requestId
        self.ok = ok
        self.data = data
        self.error = error
    }

    public func validate() throws {
        if ok && error != nil { throw CoreRPCValidationError.conflictingResult }
        if !ok && error == nil { throw CoreRPCValidationError.missingError }
    }
}

public enum CoreRPCValidationError: Error, Equatable {
    case conflictingResult
    case missingError
}
