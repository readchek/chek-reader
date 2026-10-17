import ChekReaderCore
import Foundation
import Testing

@Suite struct LocatorTests {
    @Test func decodesReadiumJSON() throws {
        let json = """
        {
          "href": "chapter1.xhtml",
          "type": "application/xhtml+xml",
          "title": "Chapter 1",
          "locations": {
            "fragments": ["p12"],
            "progression": 0.4318,
            "totalProgression": 0.07,
            "position": 14
          },
          "text": { "before": "It was ", "highlight": "a dark", "after": " and stormy night" }
        }
        """
        let locator = try JSONDecoder().decode(Locator.self, from: Data(json.utf8))
        #expect(locator.href == "chapter1.xhtml")
        #expect(locator.mediaType == "application/xhtml+xml")
        #expect(locator.locations.fragments == ["p12"])
        #expect(locator.locations.progression == 0.4318)
        #expect(locator.locations.position == 14)
        #expect(locator.text?.highlight == "a dark")
    }

    @Test func roundTrips() throws {
        let locator = Locator(
            href: "page-3.jpg",
            mediaType: "image/jpeg",
            locations: .init(progression: 0, totalProgression: 0.25, position: 3)
        )
        let data = try JSONEncoder().encode(locator)
        #expect(try JSONDecoder().decode(Locator.self, from: data) == locator)
    }

    @Test func omitsEmptyLocations() throws {
        let data = try JSONEncoder().encode(Locator(href: "a.xhtml", mediaType: "application/xhtml+xml"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["locations"] == nil)
        #expect(object["type"] as? String == "application/xhtml+xml")
    }

    @Test func toleratesMissingLocations() throws {
        let json = #"{"href": "a.xhtml", "type": "application/xhtml+xml"}"#
        let locator = try JSONDecoder().decode(Locator.self, from: Data(json.utf8))
        #expect(locator.locations == Locator.Locations())
    }
}
