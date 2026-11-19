import Foundation
import XCTest
@testable import SimpleLiveTVOS

final class TVOSReleaseServiceTests: XCTestCase {
    func testComparesAllVersionComponentsNumerically() throws {
        let installed = try XCTUnwrap(TVOSVersion("2.9.9"))
        XCTAssertGreaterThan(try XCTUnwrap(TVOSVersion("10.0.0")), installed)
        XCTAssertGreaterThan(try XCTUnwrap(TVOSVersion("2.10.0")), installed)
        XCTAssertGreaterThan(try XCTUnwrap(TVOSVersion("2.9.10")), installed)
        XCTAssertEqual(TVOSVersion("2.9.9"), installed)
        XCTAssertLessThan(try XCTUnwrap(TVOSVersion("2.9.8")), installed)
    }

    func testFindsHighestStableNativeVersionAcrossPages() async throws {
        let service = TVOSReleaseService { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "api.github.com")
            XCTAssertEqual(url.path, "/repos/xuanxuan123xuan/dart_simple_live/releases")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value
            switch page {
            case "1":
                return try Self.response(url, json: """
                [
                    {"tag_name":"tv_v99.0.0","draft":false,"prerelease":false},
                    {"tag_name":"tvos-native-v99.0.0-dev","draft":false,"prerelease":false},
                    {"tag_name":"tvos-native-v98.0.0","draft":true,"prerelease":false},
                    {"tag_name":"tvos-native-v97.0.0","draft":false,"prerelease":true},
                    {"tag_name":"tvos-native-v96.0","draft":false,"prerelease":false},
                    {"tag_name":"tvos-native-v95.+1.0","draft":false,"prerelease":false},
                    {"tag_name":"tvos-native-v2.9.9","draft":false,"prerelease":false}
                ]
                """, headers: ["Link": "<https://api.github.com/repositories/1/releases?page=2>; rel=\"next\""])
            case "2":
                return try Self.response(url, json: """
                [
                    {"tag_name":"tvos-native-v2.10.0","draft":false,"prerelease":false},
                    {"tag_name":"tvos-native-v1.0.0","draft":false,"prerelease":false}
                ]
                """, headers: ["Link": "<https://api.github.com/repositories/1/releases?page=1>; rel=\"prev\""])
            default:
                XCTFail("Unexpected releases page: \(String(describing: page))")
                throw URLError(.badURL)
            }
        }

        let latest = try await service.latestStableRelease()
        let release = try XCTUnwrap(latest)
        XCTAssertEqual(release.versionName, "2.10.0")
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/xuanxuan123xuan/dart_simple_live/releases/tag/tvos-native-v2.10.0"
        )
    }

    func testReturnsNilWhenNoStableNativeReleaseExists() async throws {
        let service = TVOSReleaseService { request in
            try Self.response(XCTUnwrap(request.url), json: """
            [
                {"tag_name":"v3.0.0","draft":false,"prerelease":false},
                {"tag_name":"tvos-native-v0.2.0-pre","draft":false,"prerelease":true}
            ]
            """)
        }
        let release = try await service.latestStableRelease()
        XCTAssertNil(release)
    }

    func testTreatsHTTPErrorAsFailureAndAllowsAnotherRequest() async throws {
        let fixture = RetryFixture()
        let service = TVOSReleaseService { request in
            try await fixture.load(XCTUnwrap(request.url))
        }
        do {
            _ = try await service.latestStableRelease()
            XCTFail("A rate limit must surface as a failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }

        let release = try await service.latestStableRelease()
        XCTAssertEqual(release?.versionName, "0.2.1")
    }

    func testMalformedSuccessfulResponseSurfacesAsFailure() async throws {
        let service = TVOSReleaseService { request in
            try Self.response(XCTUnwrap(request.url), json: "{}")
        }
        do {
            _ = try await service.latestStableRelease()
            XCTFail("An invalid release list must surface as a failure")
        } catch is DecodingError {
        }
    }

    private actor RetryFixture {
        private var attempts = 0

        func load(_ url: URL) throws -> (Data, URLResponse) {
            attempts += 1
            if attempts == 1 {
                return try response(url, status: 403, json: #"{"message":"API rate limit exceeded"}"#)
            }
            return try response(url, json: """
            [{"tag_name":"tvos-native-v0.2.1","draft":false,"prerelease":false}]
            """)
        }
    }

    private static func response(
        _ url: URL,
        status: Int = 200,
        json: String,
        headers: [String: String]? = nil
    ) throws -> (Data, URLResponse) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: headers
        ))
        return (Data(json.utf8), response)
    }
}
