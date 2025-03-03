//
//  PostHogEvent.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

public class PostHogEvent {
    public var event: String
    public var distinctId: String
    public var properties: [String: Any]
    public var timestamp: Date
    public var uuid: UUID

    enum Key: String {
        case event
        case distinctId
        case properties
        case timestamp
        case uuid
    }

    init(event: String, distinctId: String, properties: [String: Any]? = nil, timestamp: Date = Date(), uuid: UUID = .init()) {
        self.event = event
        self.distinctId = distinctId
        self.properties = properties ?? [:]
        self.timestamp = timestamp
        self.uuid = uuid
    }

    // NOTE: Ideally we would use the NSCoding behaviour but it gets needlessly complex
    // given we only need this for sending to the API
    static func fromJSON(_ data: Data) -> PostHogEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }

        return fromJSON(json)
    }

    static func fromJSON(_ json: [String: Any]) -> PostHogEvent? {
        guard let event = json["event"] as? String else { return nil }

        let timestamp = json["timestamp"] as? String ?? toISO8601String(Date())

        let timestampDate = toISO8601Date(timestamp) ?? Date()

        var properties = (json["properties"] as? [String: Any]) ?? [:]

        // back compatibility with v2
        let setProps = json["$set"] as? [String: Any]
        if setProps != nil {
            properties["$set"] = setProps
        }

        guard let distinctId = (json["distinct_id"] as? String) ?? (properties["distinct_id"] as? String) else { return nil }

        let uuid = ((json["uuid"] as? String) ?? (json["message_id"] as? String)) ?? UUID().uuidString
        let uuidObj = UUID(uuidString: uuid) ?? UUID()

        return PostHogEvent(
            event: event,
            distinctId: distinctId,
            properties: properties,
            timestamp: timestampDate,
            uuid: uuidObj
        )
    }

    func toJSON() -> [String: Any] {
        [
            "event": event,
            "distinct_id": distinctId,
            "properties": properties,
            "timestamp": toISO8601String(timestamp),
            "uuid": uuid.uuidString,
        ]
    }
}
