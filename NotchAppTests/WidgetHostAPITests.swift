import Foundation
import XCTest
import CryptoKit

@MainActor
final class WidgetHostAPITests: XCTestCase {
    func testNetworkServiceRejectsFileURLs() async {
        let service = WidgetHostNetworkService(
            makeDataTask: { _, _ in
                XCTFail("Fetch factory should not be called for rejected schemes")
                return TestNetworkDataTask()
            }
        )

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-1",
                    url: "file:///tmp/demo.txt",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected file:// fetch to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceRejectsHTTPFetchURLs() async {
        let service = WidgetHostNetworkService(
            makeDataTask: { _, _ in
                XCTFail("Fetch factory should not be called for rejected schemes")
                return TestNetworkDataTask()
            }
        )

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-http",
                    url: "http://example.com/data",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected http fetch to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceReturnsJSONTextPayload() async throws {
        let task = TestNetworkDataTask()
        var capturedRequest: URLRequest?
        let service = WidgetHostNetworkService(
            makeDataTask: { request, completion in
                capturedRequest = request
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-2",
                    url: "https://example.com/data",
                    method: "POST",
                    headers: ["content-type": "application/json"],
                    body: "{\"hello\":true}",
                    bodyEncoding: "text"
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()
        XCTAssertTrue(task.didResume)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(String(data: capturedRequest?.httpBody ?? Data(), encoding: .utf8), "{\"hello\":true}")

        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/data")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        task.complete(data: Data("{\"ok\":true}".utf8), response: response, error: nil)

        let payload = try await fetchTask.value
        XCTAssertEqual(payload.status, 200)
        XCTAssertEqual(payload.body, "{\"ok\":true}")
        XCTAssertEqual(payload.bodyEncoding, "text")
        XCTAssertEqual(payload.headers["Content-Type"], "application/json")
    }

    func testNetworkServiceRejectsRedirectedHTTPFinalURL() async {
        let task = TestNetworkDataTask()
        let service = WidgetHostNetworkService(
            makeDataTask: { _, completion in
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-redirect-final-http",
                    url: "https://example.com/data",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()

        let redirectedResponse = HTTPURLResponse(
            url: URL(string: "http://example.com/data")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.complete(data: Data("insecure".utf8), response: redirectedResponse, error: nil)

        do {
            _ = try await fetchTask.value
            XCTFail("Expected redirected insecure final URL to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceRejectsInsecureRedirectHop() async {
        WidgetHostFetchURLProtocol.reset()
        defer { WidgetHostFetchURLProtocol.reset() }

        WidgetHostFetchURLProtocol.handler = { request in
            switch request.url?.absoluteString {
            case "https://example.com/start":
                return .redirect(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": "http://example.com/middle"]
                    )!,
                    URLRequest(url: URL(string: "http://example.com/middle")!)
                )
            case "http://example.com/middle":
                return .redirect(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": "https://example.com/final"]
                    )!,
                    URLRequest(url: URL(string: "https://example.com/final")!)
                )
            case "https://example.com/final":
                return .response(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/plain"]
                    )!,
                    Data("ok".utf8)
                )
            default:
                return .failure(URLError(.badURL))
            }
        }

        let service = WidgetHostNetworkService(protocolClasses: [WidgetHostFetchURLProtocol.self])

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-redirect-hop-http",
                    url: "https://example.com/start",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected insecure redirect hop to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
            XCTAssertEqual(WidgetHostFetchURLProtocol.requestCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceCancelCancelsPendingFetchTask() async {
        let task = TestNetworkDataTask()
        let service = WidgetHostNetworkService(
            makeDataTask: { _, completion in
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-3",
                    url: "https://example.com/slow",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()
        service.cancel(RuntimeCancelRequestParams(requestId: "req-3"))
        XCTAssertTrue(task.didCancel)

        do {
            _ = try await fetchTask.value
            XCTFail("Expected cancelled fetch to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    func testNetworkServiceOpenRejectsTelScheme() {
        let service = WidgetHostNetworkService(openURLAction: { _ in
            XCTFail("openURLAction should not be called for rejected schemes")
            return false
        })

        XCTAssertThrowsError(
            try service.open(
                RuntimeBrowserOpenParams(url: "tel:123"),
                context: networkContext(kind: .openURL)
            )
        ) { error in
            XCTAssertEqual((error as? RuntimeTransportRPCError)?.code, -32010)
        }
    }

    func testNetworkServiceOpenRejectsHTTPURLs() {
        let service = WidgetHostNetworkService(openURLAction: { _ in
            XCTFail("openURLAction should not be called for rejected schemes")
            return false
        })

        XCTAssertThrowsError(
            try service.open(
                RuntimeBrowserOpenParams(url: "http://example.com"),
                context: networkContext(kind: .openURL)
            )
        ) { error in
            XCTAssertEqual((error as? RuntimeTransportRPCError)?.code, -32010)
        }
    }

    func testNetworkServiceOpenAcceptsHTTPS() throws {
        var openedURL: URL?
        let service = WidgetHostNetworkService(openURLAction: { url in
            openedURL = url
            return true
        })

        try service.open(
            RuntimeBrowserOpenParams(url: "https://example.com"),
            context: networkContext(kind: .openURL)
        )
        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")
    }

    func testHandleRoutesStorageRPCThroughWidgetHostAPI() async throws {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .object(["count": .number(1)]))
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        let response = try await api.handle(
            RuntimeTransportRequest(
                id: "1",
                method: "rpc",
                params: .object([
                    "instanceId": .string(instanceID.uuidString),
                    "sessionId": .string("session-1"),
                    "method": .string("localStorage.allItems"),
                    "params": .object([:])
                ])
            )
        )

        XCTAssertEqual(storage.lastWidgetID, "demo.widget")
        XCTAssertEqual(storage.lastInstanceID, instanceID.uuidString)
        XCTAssertEqual(storage.lastMethod, "localStorage.allItems")
        XCTAssertEqual(
            response,
            .object([
                "sessionId": .string("session-1"),
                "value": .object(["count": .number(1)])
            ])
        )
    }

    func testHandleRoutesMediaStateRPCThroughWidgetHostAPI() async throws {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let media = TestMediaHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let emptyState = WidgetHostMediaState.empty
        media.stateByMethod["getState"] = emptyState

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            media: media,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        let response = try await api.handle(
            RuntimeTransportRequest(
                id: "1",
                method: "rpc",
                params: .object([
                    "instanceId": .string(instanceID.uuidString),
                    "sessionId": .string("session-1"),
                    "method": .string("media.getState"),
                    "params": .object([:])
                ])
            )
        )

        let decoded = try XCTUnwrap(response).decode(as: DecodedRPCResponse<WidgetHostMediaState>.self)
        XCTAssertEqual(decoded.sessionId, "session-1")
        XCTAssertEqual(decoded.value, emptyState)
        XCTAssertEqual(media.invokedMethods, ["getState"])
    }

    func testHandleRoutesMediaTransportRPCThroughWidgetHostAPI() async throws {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let media = TestMediaHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            media: media,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        let response = try await api.handle(
            RuntimeTransportRequest(
                id: "1",
                method: "rpc",
                params: .object([
                    "instanceId": .string(instanceID.uuidString),
                    "sessionId": .string("session-1"),
                    "method": .string("media.play"),
                    "params": .object([:])
                ])
            )
        )

        XCTAssertEqual(
            response,
            .object([
                "sessionId": .string("session-1"),
                "value": .null
            ])
        )
        XCTAssertEqual(media.invokedMethods, ["play"])
    }

    func testHandleRoutesMediaOpenSourceAppRPCThroughWidgetHostAPI() async throws {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let media = TestMediaHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            media: media,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        let response = try await api.handle(
            RuntimeTransportRequest(
                id: "1",
                method: "rpc",
                params: .object([
                    "instanceId": .string(instanceID.uuidString),
                    "sessionId": .string("session-1"),
                    "method": .string("media.openSourceApp"),
                    "params": .object([:])
                ])
            )
        )

        XCTAssertEqual(
            response,
            .object([
                "sessionId": .string("session-1"),
                "value": .null
            ])
        )
        XCTAssertEqual(media.invokedMethods, ["openSourceApp"])
    }

    func testMediaServiceReplacesStateFromFullStreamSnapshots() {
        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12
            )
        )

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-2",
                title: "Blinding Lights",
                artist: nil,
                album: nil,
                elapsedTime: 0
            ),
            diff: false
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertNil(state.item?.artist)
        XCTAssertNil(state.item?.album)
        XCTAssertEqual(state.playbackState, .playing)
        XCTAssertTrue(state.availableActions.contains(.nextTrack))
        XCTAssertTrue(state.availableActions.contains(.previousTrack))
    }

    func testMediaServiceMergesDiffStreamUpdatesIntoExistingSnapshot() {
        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12
            )
        )

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-2",
                title: "Blinding Lights",
                artist: nil,
                album: nil,
                elapsedTime: 0
            ),
            diff: true
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertEqual(state.item?.artist, "The Weeknd")
        XCTAssertEqual(state.item?.album, "After Hours")
        XCTAssertEqual(state.timeline?.positionSeconds, 0)
    }

    func testMediaServiceAppliesExplicitNullClearsFromDiffStreamUpdates() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }
        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                processIdentifier: nil,
                bundleIdentifier: "com.apple.Music",
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12,
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        service.ingestStreamOutputLineForTesting(
            """
            {"type":"data","diff":true,"payload":{"bundleIdentifier":null,"parentApplicationBundleIdentifier":null,"uniqueIdentifier":"track-2","title":"Blinding Lights","artist":null,"album":null,"elapsedTime":0,"artworkMimeType":null,"artworkData":null}}
            """
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertNil(state.source)
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertNil(state.item?.artist)
        XCTAssertNil(state.item?.album)
        XCTAssertEqual(state.timeline?.positionSeconds, 0)
        XCTAssertNil(state.artwork)
    }

    func testMediaServicePopulatesArtworkFromAdapterSnapshots() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12,
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.artwork?.src, "notch-asset://image/\(makeTinyPNGHash())")
        XCTAssertEqual(state.artwork?.width, 1)
        XCTAssertEqual(state.artwork?.height, 1)
    }

    func testMediaServiceReusesArtworkTokensForIdenticalPayloads() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        let artworkData = makeTinyPNGData()
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: artworkData
            )
        )

        let firstArtwork = service.currentMediaStateForTesting().artwork?.src

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: artworkData
            ),
            diff: false
        )

        let secondArtwork = service.currentMediaStateForTesting().artwork?.src
        XCTAssertEqual(firstArtwork, secondArtwork)
    }

    func testMediaServicePreservesArtworkWhenNonDiffStreamUpdateOmitsArtworkForSameTrack() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                bundleIdentifier: "com.apple.Music",
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        let artworkBefore = service.currentMediaStateForTesting().artwork
        XCTAssertNotNil(artworkBefore)

        // Simulate a play/pause stream update that omits artwork (non-diff, same track).
        service.ingestStreamOutputLineForTesting(
            """
            {"type":"data","payload":{"bundleIdentifier":"com.apple.Music","playing":false,"uniqueIdentifier":"track-1","title":"After Hours","artist":"The Weeknd"}}
            """
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.id, "track-1")
        XCTAssertEqual(state.playbackState, .paused)
        XCTAssertEqual(state.artwork, artworkBefore)
    }

    func testMediaServiceClearsArtworkWhenNonDiffStreamUpdateChangesTrack() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                bundleIdentifier: "com.apple.Music",
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        // Non-diff stream update with a different track and no artwork.
        service.ingestStreamOutputLineForTesting(
            """
            {"type":"data","payload":{"bundleIdentifier":"com.apple.Music","uniqueIdentifier":"track-2","title":"Blinding Lights"}}
            """
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertNil(state.artwork)
    }

    func testMediaServicePreservesArtworkWhenContentItemIdentifierChangesButTitleIsSame() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                bundleIdentifier: "com.google.Chrome",
                contentItemIdentifier: "CID-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        let artworkBefore = service.currentMediaStateForTesting().artwork
        XCTAssertNotNil(artworkBefore)

        // Chrome generates a new contentItemIdentifier per state event,
        // even for the same track. Artwork must survive.
        service.ingestStreamOutputLineForTesting(
            """
            {"type":"data","diff":true,"payload":{"contentItemIdentifier":"CID-2","playing":false}}
            """
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.title, "After Hours")
        XCTAssertEqual(state.playbackState, .paused)
        XCTAssertEqual(state.artwork, artworkBefore)
    }

    func testMediaServiceClearsInheritedArtworkWhenTrackChangesBeforeNewArtworkArrives() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: makeTinyPNGData()
            )
        )

        service.ingestStreamOutputLineForTesting(
            """
            {"type":"data","diff":true,"payload":{"uniqueIdentifier":"track-2","title":"Blinding Lights"}}
            """
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertNil(state.artwork)
    }

    func testMediaServiceIgnoresInvalidArtworkPayloads() {
        WidgetImagePipeline.resetHostAssetsForTesting()
        defer { WidgetImagePipeline.resetHostAssetsForTesting() }

        let service = WidgetHostMediaService(log: { _ in })
        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artworkMimeType: "image/png",
                artworkData: Data("not-an-image".utf8)
            )
        )

        XCTAssertNil(service.currentMediaStateForTesting().artwork)
    }

    func testMediaServiceNextTrackOnlySendsTheCommandAndKeepsTheCurrentStateUntilTheStreamUpdates() async throws {
        var adapterCalls: [[String]] = []
        let service = WidgetHostMediaService(
            runAdapterCommand: { arguments in
                adapterCalls.append(arguments)
                switch arguments {
                case ["send", "4"]:
                    return ""
                default:
                    XCTFail("Unexpected adapter arguments: \(arguments)")
                    return ""
                }
            },
            log: { _ in }
        )

        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12
            )
        )

        try await service.nextTrack()
        let state = service.currentMediaStateForTesting()

        XCTAssertEqual(adapterCalls, [["send", "4"]])
        XCTAssertEqual(state.item?.title, "After Hours")
        XCTAssertEqual(state.item?.id, "track-1")
        XCTAssertTrue(state.availableActions.contains(.nextTrack))
        XCTAssertTrue(state.availableActions.contains(.previousTrack))

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-2",
                title: "Blinding Lights",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 0
            ),
            diff: true
        )

        let updatedState = service.currentMediaStateForTesting()
        XCTAssertEqual(updatedState.item?.title, "Blinding Lights")
        XCTAssertEqual(updatedState.item?.id, "track-2")
    }

    func testMediaServiceGetStateFetchesTheCurrentSnapshotWhenTheStreamHasNotEmittedYet() async throws {
        var adapterCalls: [[String]] = []
        let service = WidgetHostMediaService(
            runAdapterCommand: { arguments in
                adapterCalls.append(arguments)
                switch arguments {
                case ["get", "--now"]:
                    return encodeMediaAdapterSnapshot(
                        makeMediaAdapterSnapshot(
                            uniqueIdentifier: "track-2",
                            title: "Blinding Lights",
                            artist: "The Weeknd",
                            album: "After Hours",
                            elapsedTime: 0
                        )
                    )
                default:
                    XCTFail("Unexpected adapter arguments: \(arguments)")
                    return ""
                }
            },
            log: { _ in }
        )

        let state = try await service.getState()
        XCTAssertEqual(adapterCalls, [["get", "--now"]])
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testMediaServiceGetStateReturnsEmptyWhenTheAdapterReportsNoSession() async throws {
        var adapterCalls: [[String]] = []
        let service = WidgetHostMediaService(
            runAdapterCommand: { arguments in
                adapterCalls.append(arguments)
                switch arguments {
                case ["get", "--now"]:
                    return "null"
                default:
                    XCTFail("Unexpected adapter arguments: \(arguments)")
                    return ""
                }
            },
            log: { _ in }
        )

        let state = try await service.getState()
        XCTAssertEqual(adapterCalls, [["get", "--now"]])
        XCTAssertEqual(state, .empty)
    }

    func testMediaServiceBuildsPlaybackStateFromPartialStreamUpdatesAfterStartingEmpty() {
        let service = WidgetHostMediaService(log: { _ in })

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: nil,
                title: nil,
                artist: nil,
                album: nil
            )
        )

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                processIdentifier: nil,
                bundleIdentifier: nil,
                playing: nil,
                title: "Blinding Lights",
                artist: "The Weeknd",
                album: "After Hours",
                duration: nil,
                timestamp: nil,
                playbackRate: nil,
                prohibitsSkip: nil,
                uniqueIdentifier: "track-2",
                contentItemIdentifier: nil
            ),
            diff: true
        )

        let state = service.currentMediaStateForTesting()
        XCTAssertEqual(state.item?.title, "Blinding Lights")
        XCTAssertEqual(state.item?.artist, "The Weeknd")
        XCTAssertEqual(state.item?.album, "After Hours")
        XCTAssertEqual(state.item?.id, "track-2")
        XCTAssertEqual(state.playbackState, .playing)
    }

    func testMediaServiceClearsTheStateWhenTheStreamEmitsAnEmptyFullSnapshot() {
        let service = WidgetHostMediaService(log: { _ in })

        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12
            )
        )

        service.ingestStreamSnapshotForTesting(
            makeMediaAdapterSnapshot(
                processIdentifier: nil,
                bundleIdentifier: nil,
                parentApplicationBundleIdentifier: nil,
                playing: nil,
                title: nil,
                artist: nil,
                album: nil,
                duration: nil,
                elapsedTime: nil,
                elapsedTimeNow: nil,
                timestamp: nil,
                playbackRate: nil,
                prohibitsSkip: nil,
                uniqueIdentifier: nil,
                contentItemIdentifier: nil
            ),
            diff: false
        )

        XCTAssertEqual(service.currentMediaStateForTesting(), .empty)
    }

    func testMediaServiceOpenSourceAppUsesTheCurrentSourceBundleIdentifier() async throws {
        var openedBundleIdentifiers: [String] = []
        let service = WidgetHostMediaService(
            openApplication: { bundleIdentifier in
                openedBundleIdentifiers.append(bundleIdentifier)
                return true
            },
            log: { _ in }
        )

        service.ingestSnapshotForTesting(
            makeMediaAdapterSnapshot(
                bundleIdentifier: "com.google.Chrome",
                uniqueIdentifier: "track-1",
                title: "After Hours",
                artist: "The Weeknd",
                album: "After Hours",
                elapsedTime: 12
            )
        )

        try await service.openSourceApp()

        XCTAssertEqual(openedBundleIdentifiers, ["com.google.Chrome"])
    }

    func testMediaServiceOpenSourceAppDoesNothingWhenThereIsNoActiveSource() async throws {
        var openedBundleIdentifiers: [String] = []
        let service = WidgetHostMediaService(
            openApplication: { bundleIdentifier in
                openedBundleIdentifiers.append(bundleIdentifier)
                return true
            },
            runAdapterCommand: { arguments in
                switch arguments {
                case ["get", "--now"]:
                    return "null"
                default:
                    XCTFail("Unexpected adapter arguments: \(arguments)")
                    return ""
                }
            },
            log: { _ in }
        )

        try await service.openSourceApp()

        XCTAssertTrue(openedBundleIdentifiers.isEmpty)
    }

    func testHandleRejectsUnknownWidgetHostRPCMethod() async {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        do {
            _ = try await api.handle(
                RuntimeTransportRequest(
                    id: "1",
                    method: "rpc",
                    params: .object([
                        "instanceId": .string(instanceID.uuidString),
                        "sessionId": .string("session-1"),
                        "method": .string("unknown.method"),
                        "params": .object([:])
                    ])
                )
            )
            XCTFail("Expected unknown method to fail")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32601)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHandleRejectsSessionMismatchBeforeDispatch() async {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)
        _ = sessionManager.acceptsWorkerSession(instanceID: instanceID, sessionId: "session-1")

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        do {
            _ = try await api.handle(
                RuntimeTransportRequest(
                    id: "1",
                    method: "rpc",
                    params: .object([
                        "instanceId": .string(instanceID.uuidString),
                        "sessionId": .string("session-2"),
                        "method": .string("localStorage.allItems"),
                        "params": .object([:])
                    ])
                )
            )
            XCTFail("Expected session mismatch to fail")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32004)
            XCTAssertNil(storage.lastMethod)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private func networkContext(
    kind: WidgetHostNetworkRequestKind
) -> WidgetHostNetworkContext {
    WidgetHostNetworkContext(
        widgetID: "demo.widget",
        instanceID: UUID().uuidString,
        kind: kind
    )
}

private final class TestNetworkDataTask: WidgetHostNetworkDataTask {
    var didResume = false
    var didCancel = false
    var completion: ((Data?, URLResponse?, Error?) -> Void)?

    func resume() {
        didResume = true
    }

    func cancel() {
        didCancel = true
        completion?(nil, nil, URLError(.cancelled))
    }

    func complete(data: Data?, response: URLResponse?, error: Error?) {
        completion?(data, response, error)
    }
}

private final class WidgetHostFetchURLProtocol: URLProtocol {
    enum Event {
        case response(HTTPURLResponse, Data)
        case redirect(HTTPURLResponse, URLRequest)
        case failure(Error)
    }

    static var handler: ((URLRequest) -> Event)?
    static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch handler(request) {
        case .response(let response, let data):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let response, let redirectedRequest):
            client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestStorageHandler: WidgetHostLocalStorageHandling {
    var result: RuntimeJSONValue
    var lastWidgetID: String?
    var lastInstanceID: String?
    var lastMethod: String?

    init(result: RuntimeJSONValue) {
        self.result = result
    }

    func handleRPC(widgetID: String, instanceID: String, method: String, params: RuntimeJSONValue?) throws -> RuntimeJSONValue {
        lastWidgetID = widgetID
        lastInstanceID = instanceID
        lastMethod = method
        return result
    }

    func setPreferenceValue(widgetID: String, instanceID: String, name: String, value: RuntimeJSONValue?) throws {
        _ = widgetID
        _ = instanceID
        _ = name
        _ = value
    }

    func preferenceValues(widgetID: String, instanceID: String) -> [String: RuntimeJSONValue] {
        _ = widgetID
        _ = instanceID
        return [:]
    }
}

@MainActor
private final class TestNetworkHandler: WidgetHostNetworkHandling {
    func fetch(
        _ params: RuntimeFetchRequestParams,
        context: WidgetHostNetworkContext
    ) async throws -> RuntimeFetchResponsePayload {
        _ = context
        XCTFail("Network handler should not be called in this test")
        return RuntimeFetchResponsePayload(status: 200, statusText: "ok", headers: [:], body: nil, bodyEncoding: "text")
    }

    func cancel(_ params: RuntimeCancelRequestParams) {
        XCTFail("Network handler should not be called in this test")
    }

    func open(
        _ params: RuntimeBrowserOpenParams,
        context: WidgetHostNetworkContext
    ) throws {
        _ = context
        XCTFail("Network handler should not be called in this test")
    }
}

private struct DecodedRPCResponse<Value: Decodable>: Decodable {
    var sessionId: String
    var value: Value
}

private func makeMediaAdapterSnapshot(
    processIdentifier: Int? = 1234,
    bundleIdentifier: String? = "com.apple.Music",
    parentApplicationBundleIdentifier: String? = nil,
    playing: Bool? = true,
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    duration: Double? = 240,
    elapsedTime: Double? = nil,
    elapsedTimeNow: Double? = nil,
    timestamp: String? = "2026-04-06T10:00:00Z",
    playbackRate: Double? = 1,
    prohibitsSkip: Bool? = false,
    uniqueIdentifier: String? = nil,
    contentItemIdentifier: String? = nil,
    artworkMimeType: String? = nil,
    artworkData: Data? = nil
) -> WidgetHostMediaAdapterSnapshot {
    WidgetHostMediaAdapterSnapshot(
        processIdentifier: processIdentifier,
        bundleIdentifier: bundleIdentifier,
        parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
        playing: playing,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        elapsedTime: elapsedTime,
        elapsedTimeNow: elapsedTimeNow,
        timestamp: timestamp,
        playbackRate: playbackRate,
        prohibitsSkip: prohibitsSkip,
        uniqueIdentifier: uniqueIdentifier,
        contentItemIdentifier: contentItemIdentifier,
        artworkMimeType: artworkMimeType,
        artworkData: artworkData
    )
}

private func encodeMediaAdapterSnapshot(_ snapshot: WidgetHostMediaAdapterSnapshot?) -> String {
    if let snapshot {
        let data = try! JSONEncoder().encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    return "null"
}

private func makeTinyPNGData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2pQioAAAAASUVORK5CYII=")!
}

private func makeTinyPNGHash() -> String {
    SHA256.hash(data: makeTinyPNGData()).map { String(format: "%02x", $0) }.joined()
}

@MainActor
private final class TestMediaHandler: WidgetHostMediaHandling {
    var stateByMethod: [String: WidgetHostMediaState] = [:]
    var invokedMethods: [String] = []

    func getState() async throws -> WidgetHostMediaState {
        invokedMethods.append("getState")
        return stateByMethod["getState"] ?? .empty
    }

    func play() async throws {
        invokedMethods.append("play")
    }

    func pause() async throws {
        invokedMethods.append("pause")
    }

    func togglePlayPause() async throws {
        invokedMethods.append("togglePlayPause")
    }

    func nextTrack() async throws {
        invokedMethods.append("nextTrack")
    }

    func previousTrack() async throws {
        invokedMethods.append("previousTrack")
    }

    func openSourceApp() async throws {
        invokedMethods.append("openSourceApp")
    }
}
