//
//  WatchRiskPayload.swift
//  NALI Migraine Log
//
//  Typed risk summary pushed from the iPhone to the Watch. Only aggregate
//  numbers and short display strings travel; no entry data.
//

import Foundation

struct WatchRiskPayload: Codable, Equatable, Sendable {
    struct Factor: Codable, Equatable, Sendable {
        var name: String
        var contribution: Double
        var icon: String
        var detail: String
    }

    static let payloadKey = "riskUpdateV2"
    /// Pre-typed dictionary payload still emitted by older phone builds.
    static let legacyPayloadKey = "riskUpdate"
    static let maxFactors = 3
    static let maxRecommendations = 3
    static let maxDetailLength = 200

    var riskPercentage: Int
    var riskLevel: String
    var factors: [Factor]
    var recommendations: [String]
    var confidence: Double
    var timestamp: Date

    init(riskScore: MigraineRiskScore, now: Date = Date()) {
        riskPercentage = riskScore.riskPercentage
        riskLevel = riskScore.riskLevel.rawValue
        // Reproductive-health context never leaves the phone; the
        // overall percentage still reflects it.
        factors = riskScore.topFactors
            .filter { !$0.isSensitive }
            .prefix(Self.maxFactors)
            .map {
                Factor(
                    name: $0.name,
                    contribution: $0.contribution,
                    icon: $0.icon,
                    detail: String($0.detail.prefix(Self.maxDetailLength))
                )
            }
        recommendations = Array(
            riskScore.recommendations
                .filter { !PerimenstrualWindow.sensitiveRecommendations.contains($0) }
                .prefix(Self.maxRecommendations)
        )
        confidence = riskScore.confidence
        timestamp = now
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    static func decode(_ data: Data) -> WatchRiskPayload? {
        guard let payload = try? decoder.decode(WatchRiskPayload.self, from: data) else { return nil }
        return payload.validated()
    }

    /// Reads either the typed `riskUpdateV2` blob or a legacy `riskUpdate`
    /// dictionary (whose keys match `CodingKeys`) from a WatchConnectivity payload.
    static func decode(from payload: [String: Any]) -> WatchRiskPayload? {
        if let data = payload[payloadKey] as? Data {
            return decode(data)
        }
        if let legacy = payload[legacyPayloadKey] as? [String: Any],
           JSONSerialization.isValidJSONObject(legacy),
           let data = try? JSONSerialization.data(withJSONObject: legacy) {
            return decode(data)
        }
        return nil
    }

    /// Age after which the Watch flags a synced score as possibly out of date.
    static let staleAfter: TimeInterval = 6 * 3_600

    func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(timestamp) > Self.staleAfter
    }

    /// Last-writer-wins on the phone's timestamp; an equal timestamp is
    /// re-adopted so a re-delivered payload converges instead of stalling.
    static func shouldAdopt(_ incoming: WatchRiskPayload, over current: WatchRiskPayload?) -> Bool {
        guard let current else { return true }
        return incoming.timestamp >= current.timestamp
    }

    /// Clamps values so a corrupt counterpart cannot drive the Watch UI out of range.
    func validated() -> WatchRiskPayload? {
        guard (0...100).contains(riskPercentage),
              confidence.isFinite,
              timestamp.timeIntervalSince1970 > 0 else { return nil }
        var copy = self
        copy.confidence = min(max(confidence, 0), 1)
        copy.factors = Array(factors.prefix(Self.maxFactors)).filter { $0.contribution.isFinite }
        copy.recommendations = Array(recommendations.prefix(Self.maxRecommendations))
        return copy
    }
}
