import Foundation

public enum StreamProtocol: String, Codable, Sendable {
    case hls
    case flv
    case rtmp
    case unknown
}

public struct PlaybackResource: Codable, Equatable, Sendable {
    public let url: URL
    public let protocolKind: StreamProtocol
    public let headers: [String: String]
    public let quality: String?
    public let lineIndex: Int

    public init(
        url: URL,
        protocolKind: StreamProtocol,
        headers: [String: String] = [:],
        quality: String? = nil,
        lineIndex: Int = 0
    ) {
        self.url = url
        self.protocolKind = protocolKind
        self.headers = headers
        self.quality = quality
        self.lineIndex = lineIndex
    }
}

public enum PlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case buffering
    case playing
    case paused
    case failed(kind: String, message: String)
    case stopped
}

public struct PlaybackAttempt: Equatable, Sendable {
    public let resource: PlaybackResource
    public let generation: Int

    public init(resource: PlaybackResource, generation: Int) {
        self.resource = resource
        self.generation = generation
    }
}

public enum PlaybackFailoverError: Error, Equatable, Sendable {
    case noResources
    case staleGeneration
    case allResourcesFailed
}

public struct PlaybackFailoverController: Sendable {
    public private(set) var state: PlaybackState = .idle
    public private(set) var generation = 0
    public private(set) var currentLine: Int?

    private var resources: [PlaybackResource] = []
    private var nextIndex = 0

    public init() {}

    public mutating func begin(resources: [PlaybackResource]) throws -> PlaybackAttempt {
        guard !resources.isEmpty else { throw PlaybackFailoverError.noResources }
        generation += 1
        self.resources = resources
        nextIndex = 0
        currentLine = nil
        state = .preparing
        return PlaybackAttempt(resource: resources[0], generation: generation)
    }

    public mutating func failCurrent(generation: Int) throws -> PlaybackAttempt {
        guard generation == self.generation else { throw PlaybackFailoverError.staleGeneration }
        nextIndex += 1
        guard nextIndex < resources.count else {
            state = .failed(kind: "playback", message: "所有播放线路均失败")
            throw PlaybackFailoverError.allResourcesFailed
        }
        state = .preparing
        return PlaybackAttempt(resource: resources[nextIndex], generation: generation)
    }

    public mutating func markPlaying(lineIndex: Int, generation: Int) throws {
        guard generation == self.generation else { throw PlaybackFailoverError.staleGeneration }
        guard resources.indices.contains(lineIndex) else { throw PlaybackFailoverError.noResources }
        currentLine = lineIndex
        state = .playing
    }

    public mutating func markPaused(generation: Int) throws {
        guard generation == self.generation else { throw PlaybackFailoverError.staleGeneration }
        state = .paused
    }

    public mutating func stop() {
        generation += 1
        state = .stopped
        currentLine = nil
        resources.removeAll()
        nextIndex = 0
    }
}
