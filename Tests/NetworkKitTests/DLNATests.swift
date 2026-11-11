#if canImport(Network)
import Foundation
import Testing
@testable import NetKitApple

@Suite("DLNA Module")
struct DLNATests {

    // MARK: - SSDP Message Parsing

    @Suite("SSDP Message Parsing")
    struct SSDPParsingTests {

        @Test("Parse NOTIFY alive message")
        func parseNotifyAlive() {
            let raw = """
            NOTIFY * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            CACHE-CONTROL: max-age=1800\r
            LOCATION: http://192.168.1.10:8080/description.xml\r
            NT: urn:schemas-upnp-org:device:MediaServer:1\r
            NTS: ssdp:alive\r
            SERVER: macOS/1.0 UPnP/1.0 BrainyTube/1.0\r
            USN: uuid:abc-123::urn:schemas-upnp-org:device:MediaServer:1\r
            \r

            """

            let message = SSDPMessage.parse(raw)
            #expect(message != nil)
            #expect(message?.type == .alive)
            #expect(message?.usn == "uuid:abc-123::urn:schemas-upnp-org:device:MediaServer:1")
            #expect(message?.location == "http://192.168.1.10:8080/description.xml")
            #expect(message?.searchTarget == "urn:schemas-upnp-org:device:MediaServer:1")
            #expect(message?.server == "macOS/1.0 UPnP/1.0 BrainyTube/1.0")
            #expect(message?.maxAge == 1800)
        }

        @Test("Parse NOTIFY byebye message")
        func parseNotifyByebye() {
            let raw = """
            NOTIFY * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            NT: urn:schemas-upnp-org:device:MediaServer:1\r
            NTS: ssdp:byebye\r
            USN: uuid:abc-123::urn:schemas-upnp-org:device:MediaServer:1\r
            \r

            """

            let message = SSDPMessage.parse(raw)
            #expect(message != nil)
            #expect(message?.type == .byebye)
            #expect(message?.usn == "uuid:abc-123::urn:schemas-upnp-org:device:MediaServer:1")
        }

        @Test("Parse M-SEARCH response")
        func parseSearchResponse() {
            let raw = """
            HTTP/1.1 200 OK\r
            CACHE-CONTROL: max-age=1800\r
            LOCATION: http://192.168.1.10:8080/description.xml\r
            ST: urn:schemas-upnp-org:device:MediaServer:1\r
            SERVER: macOS/1.0\r
            USN: uuid:test-456\r
            \r

            """

            let message = SSDPMessage.parse(raw)
            #expect(message != nil)
            #expect(message?.type == .searchResponse)
            #expect(message?.location == "http://192.168.1.10:8080/description.xml")
            #expect(message?.searchTarget == "urn:schemas-upnp-org:device:MediaServer:1")
        }

        @Test("Parse M-SEARCH request")
        func parseMSearch() {
            let raw = """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 3\r
            ST: ssdp:all\r
            \r

            """

            let message = SSDPMessage.parse(raw)
            #expect(message != nil)
            #expect(message?.type == .search)
        }

        @Test("Returns nil for garbage input")
        func parseGarbage() {
            let message = SSDPMessage.parse("not a valid ssdp message")
            #expect(message == nil)
        }

        @Test("Returns nil for empty data")
        func parseEmpty() {
            let message = SSDPMessage.parse(Data())
            #expect(message == nil)
        }
    }

    // MARK: - SSDP Message Serialization

    @Suite("SSDP Message Serialization")
    struct SSDPSerializationTests {

        @Test("notifyAlive round-trips through parser")
        func notifyAliveRoundTrip() {
            let data = SSDPMessage.notifyAlive(
                location: "http://10.0.0.1:9090/description.xml",
                usn: "uuid:round-trip",
                searchTarget: SSDPConstants.mediaServerType,
                server: "Test/1.0"
            )
            let parsed = SSDPMessage.parse(data)
            #expect(parsed?.type == .alive)
            #expect(parsed?.usn == "uuid:round-trip")
            #expect(parsed?.location == "http://10.0.0.1:9090/description.xml")
        }

        @Test("notifyByebye round-trips through parser")
        func notifyByebyeRoundTrip() {
            let data = SSDPMessage.notifyByebye(
                usn: "uuid:bye-test",
                searchTarget: SSDPConstants.mediaServerType
            )
            let parsed = SSDPMessage.parse(data)
            #expect(parsed?.type == .byebye)
            #expect(parsed?.usn == "uuid:bye-test")
        }

        @Test("mSearch round-trips through parser")
        func mSearchRoundTrip() {
            let data = SSDPMessage.mSearch(searchTarget: SSDPConstants.mediaServerType)
            let parsed = SSDPMessage.parse(data)
            #expect(parsed?.type == .search)
            #expect(parsed?.searchTarget == SSDPConstants.mediaServerType)
        }

        @Test("searchResponse round-trips through parser")
        func searchResponseRoundTrip() {
            let data = SSDPMessage.searchResponse(
                location: "http://10.0.0.1:8080/desc.xml",
                usn: "uuid:resp-test",
                searchTarget: SSDPConstants.mediaServerType,
                server: "Test/1.0"
            )
            let parsed = SSDPMessage.parse(data)
            #expect(parsed?.type == .searchResponse)
            #expect(parsed?.usn == "uuid:resp-test")
        }
    }

    // MARK: - DIDL-Lite XML Generation

    @Suite("DIDL-Lite XML")
    struct DIDLLiteTests {

        @Test("Generates valid DIDL-Lite for a single item")
        func singleItemDIDL() {
            let item = DLNAMediaItem(
                id: "abc123",
                title: "Test Video",
                creator: "Test Channel",
                duration: 3661,
                filePath: "/tmp/video.mp4",
                thumbnailPath: "/tmp/thumb.jpg",
                mimeType: "video/mp4",
                fileSize: 1_000_000
            )

            let xml = ContentDirectory.didlLite(items: [item], baseURL: "http://10.0.0.1:8080")

            #expect(xml.contains("DIDL-Lite"))
            #expect(xml.contains("<dc:title>Test Video</dc:title>"))
            #expect(xml.contains("<dc:creator>Test Channel</dc:creator>"))
            #expect(xml.contains("object.item.videoItem"))
            #expect(xml.contains("http://10.0.0.1:8080/media/abc123/"))
            #expect(xml.contains("duration=\"1:01:01\""))
            #expect(xml.contains("size=\"1000000\""))
            #expect(xml.contains("video/mp4"))
            #expect(xml.contains("albumArtURI"))
        }

        @Test("Generates DIDL-Lite without optional fields")
        func minimalItemDIDL() {
            let item = DLNAMediaItem(
                id: "minimal",
                title: "Minimal",
                filePath: "/tmp/vid.mp4"
            )

            let xml = ContentDirectory.didlLite(items: [item], baseURL: "http://localhost:8080")

            #expect(xml.contains("<dc:title>Minimal</dc:title>"))
            #expect(!xml.contains("<dc:creator>"))
            #expect(!xml.contains("duration="))
            #expect(!xml.contains("albumArtURI"))
        }

        @Test("Escapes XML special characters in title")
        func xmlEscaping() {
            let item = DLNAMediaItem(
                id: "esc",
                title: "Test <Video> & \"Stuff\"",
                filePath: "/tmp/v.mp4"
            )

            let xml = ContentDirectory.didlLite(items: [item], baseURL: "http://localhost")

            #expect(xml.contains("Test &lt;Video&gt; &amp; &quot;Stuff&quot;"))
            #expect(!xml.contains("Test <Video>"))
        }

        @Test("Handles empty items array")
        func emptyDIDL() {
            let xml = ContentDirectory.didlLite(items: [], baseURL: "http://localhost")
            #expect(xml.contains("DIDL-Lite"))
            #expect(!xml.contains("<item"))
        }

        @Test("Multiple items in DIDL-Lite")
        func multipleItems() {
            let items = (0..<3).map {
                DLNAMediaItem(id: "item\($0)", title: "Video \($0)", filePath: "/tmp/\($0).mp4")
            }

            let xml = ContentDirectory.didlLite(items: items, baseURL: "http://localhost")
            #expect(xml.contains("item0"))
            #expect(xml.contains("item1"))
            #expect(xml.contains("item2"))
        }
    }

    // MARK: - Content Directory Browse

    @Suite("Content Directory")
    struct ContentDirectoryTests {

        @Test("Concurrent setItems / allItems / browse never tear the item list")
        func concurrentAccessNeverTearsTheList() async {
            let directory = ContentDirectory()
            let small = (0..<3).map { DLNAMediaItem(id: "s\($0)", title: "S\($0)", filePath: "/s\($0).mp4") }
            let large = (0..<50).map { DLNAMediaItem(id: "l\($0)", title: "L\($0)", filePath: "/l\($0).mp4") }

            await withTaskGroup(of: Void.self) { group in
                for index in 0..<200 {
                    group.addTask {
                        if index % 2 == 0 {
                            directory.setItems(index % 4 == 0 ? small : large)
                        } else {
                            let snapshot = directory.allItems
                            // Every snapshot is one of the two whole lists, never a mixture.
                            #expect(snapshot.isEmpty || snapshot.count == small.count || snapshot.count == large.count)
                            _ = directory.browse(objectID: "0")
                        }
                    }
                }
            }
            #expect(directory.count == small.count || directory.count == large.count)
        }

        @Test("Browse root returns all items")
        func browseRoot() {
            let cd = ContentDirectory()
            cd.setItems([
                DLNAMediaItem(id: "a", title: "A", filePath: "/a.mp4"),
                DLNAMediaItem(id: "b", title: "B", filePath: "/b.mp4"),
            ])

            let result = cd.browse(objectID: "0")
            #expect(result.totalMatches == 2)
            #expect(result.numberReturned == 2)
            #expect(result.items.count == 2)
        }

        @Test("Browse with pagination")
        func browsePaginated() {
            let cd = ContentDirectory()
            cd.setItems((0..<10).map {
                DLNAMediaItem(id: "\($0)", title: "V\($0)", filePath: "/\($0).mp4")
            })

            let page1 = cd.browse(objectID: "0", startIndex: 0, requestedCount: 3)
            #expect(page1.numberReturned == 3)
            #expect(page1.totalMatches == 10)
            #expect(page1.items[0].id == "0")

            let page2 = cd.browse(objectID: "0", startIndex: 3, requestedCount: 3)
            #expect(page2.numberReturned == 3)
            #expect(page2.items[0].id == "3")
        }

        @Test("Browse single item by ID")
        func browseSingleItem() {
            let cd = ContentDirectory()
            cd.setItems([
                DLNAMediaItem(id: "target", title: "Target", filePath: "/t.mp4"),
            ])

            let result = cd.browse(objectID: "target")
            #expect(result.totalMatches == 1)
            #expect(result.items[0].title == "Target")
        }

        @Test("Browse unknown objectID returns empty")
        func browseUnknown() {
            let cd = ContentDirectory()
            let result = cd.browse(objectID: "nonexistent")
            #expect(result.totalMatches == 0)
            #expect(result.items.isEmpty)
        }

        @Test("Search by title")
        func searchByTitle() {
            let cd = ContentDirectory()
            cd.setItems([
                DLNAMediaItem(id: "1", title: "Swift Tutorial", filePath: "/1.mp4"),
                DLNAMediaItem(id: "2", title: "Rust Guide", filePath: "/2.mp4"),
                DLNAMediaItem(id: "3", title: "Advanced Swift", filePath: "/3.mp4"),
            ])

            let results = cd.search(query: "swift")
            #expect(results.count == 2)
            #expect(results.allSatisfy { $0.title.lowercased().contains("swift") })
        }

        @Test("Count reflects setItems")
        func countUpdates() {
            let cd = ContentDirectory()
            #expect(cd.isEmpty)

            cd.setItems([DLNAMediaItem(id: "1", title: "V", filePath: "/v.mp4")])
            #expect(cd.count == 1)

            cd.setItems([])
            #expect(cd.isEmpty)
        }
    }

    // MARK: - Device Description XML

    @Suite("Device Description")
    struct DeviceDescriptionTests {

        @Test("Generates valid device description XML")
        func deviceDescription() {
            let xml = ContentDirectory.deviceDescriptionXML(
                friendlyName: "Test Server",
                uuid: "test-uuid-123",
                baseURL: "http://192.168.1.10:8080"
            )

            #expect(xml.contains("Test Server"))
            #expect(xml.contains("test-uuid-123"))
            #expect(xml.contains(SSDPConstants.mediaServerType))
            #expect(xml.contains(SSDPConstants.contentDirectoryType))
            #expect(xml.contains("/ContentDirectory/control"))
        }
    }

    // MARK: - SOAP Browse Response

    @Suite("SOAP Envelope")
    struct SOAPTests {

        @Test("Browse response envelope wraps DIDL-Lite")
        func browseResponseEnvelope() {
            let didl = "<DIDL-Lite>test</DIDL-Lite>"
            let envelope = ContentDirectory.browseResponseEnvelope(
                didlLite: didl,
                totalMatches: 5,
                numberReturned: 3
            )

            #expect(envelope.contains("s:Envelope"))
            #expect(envelope.contains("BrowseResponse"))
            #expect(envelope.contains("<TotalMatches>5</TotalMatches>"))
            #expect(envelope.contains("<NumberReturned>3</NumberReturned>"))
            #expect(envelope.contains("<Result>"))
        }
    }

    // MARK: - DLNAMediaItem

    @Suite("DLNAMediaItem")
    struct MediaItemTests {

        @Test("formattedDuration formats correctly")
        func formattedDuration() {
            let item = DLNAMediaItem(id: "1", title: "T", duration: 7261, filePath: "/v.mp4")
            #expect(item.formattedDuration == "2:01:01")
        }

        @Test("formattedDuration nil when no duration")
        func noDuration() {
            let item = DLNAMediaItem(id: "1", title: "T", filePath: "/v.mp4")
            #expect(item.formattedDuration == nil)
        }

        @Test("fileExtension derived from mimeType")
        func fileExtension() {
            #expect(DLNAMediaItem(id: "1", title: "T", filePath: "/v", mimeType: "video/mp4").fileExtension == "mp4")
            #expect(DLNAMediaItem(id: "1", title: "T", filePath: "/v", mimeType: "video/x-matroska").fileExtension == "mkv")
            #expect(DLNAMediaItem(id: "1", title: "T", filePath: "/v", mimeType: "video/webm").fileExtension == "webm")
            #expect(DLNAMediaItem(id: "1", title: "T", filePath: "/v", mimeType: "image/jpeg").fileExtension == "jpg")
            #expect(DLNAMediaItem(id: "1", title: "T", filePath: "/v", mimeType: "application/octet-stream").fileExtension == "bin")
        }
    }

    // MARK: - Sidecar Metadata

    @Suite("Sidecar Metadata")
    struct SidecarMetadataTests {

        @Test("DLNAMediaItem stores app-specific metadata")
        func metadataStorage() {
            let item = DLNAMediaItem(
                id: "yt123",
                title: "Test",
                filePath: "/v.mp4",
                metadata: ["youtubeID": "yt123", "quality": "1080p", "subtitlePath": "/subs/en.vtt"]
            )

            #expect(item.metadata["youtubeID"] == "yt123")
            #expect(item.metadata["quality"] == "1080p")
            #expect(item.metadata["subtitlePath"] == "/subs/en.vtt")
        }

        @Test("DLNAMediaItem defaults to empty metadata")
        func emptyMetadata() {
            let item = DLNAMediaItem(id: "1", title: "T", filePath: "/v.mp4")
            #expect(item.metadata.isEmpty)
        }

        @Test("Items with different metadata are not equal")
        func metadataEquality() {
            let a = DLNAMediaItem(id: "1", title: "T", filePath: "/v.mp4", metadata: ["key": "val"])
            let b = DLNAMediaItem(id: "1", title: "T", filePath: "/v.mp4", metadata: [:])
            #expect(a != b)
        }
    }

    // MARK: - SSDPSearchResponder

    @Suite("SSDPSearchResponder")
    struct SSDPSearchResponderTests {

        @Test("Responder initializes with correct parameters")
        func initialization() {
            let responder = SSDPSearchResponder(
                location: "http://10.0.0.1:8080/description.xml",
                usn: "uuid:test-responder"
            )
            // Verify it can be started and stopped without crashing
            responder.start()
            responder.stop()
        }
    }

    // MARK: - DIDL-Lite Parsing (DLNABrowser)

    @Suite("DIDL-Lite Parsing")
    struct DIDLParsingTests {

        @Test("Parse DIDL-Lite items from SOAP response")
        func parseFromSOAP() {
            let didl = ContentDirectory.didlLite(
                items: [
                    DLNAMediaItem(
                        id: "vid1",
                        title: "My Video",
                        creator: "Channel",
                        duration: 120,
                        filePath: "http://server/media/vid1/vid1.mp4",
                        mimeType: "video/mp4",
                        fileSize: 50000
                    ),
                ],
                baseURL: "http://server"
            )

            let envelope = ContentDirectory.browseResponseEnvelope(
                didlLite: didl,
                totalMatches: 1,
                numberReturned: 1
            )

            let items = DLNABrowser.parseDidlLiteFromSOAP(envelope)
            #expect(items.count == 1)
            #expect(items[0].id == "vid1")
            #expect(items[0].title == "My Video")
            #expect(items[0].creator == "Channel")
        }

        @Test("Parse empty SOAP response")
        func parseEmptySOAP() {
            let envelope = ContentDirectory.browseResponseEnvelope(
                didlLite: ContentDirectory.didlLite(items: [], baseURL: "http://x"),
                totalMatches: 0,
                numberReturned: 0
            )

            let items = DLNABrowser.parseDidlLiteFromSOAP(envelope)
            #expect(items.isEmpty)
        }
    }

    // MARK: - Queue labels (#18 review: one reverse-DNS root, spelled once)

    @Suite("NetKit queue labels")
    struct QueueLabelTests {
        @Test("every queue label is under OBYW.one's one.obyw.netkit root, and none repeats")
        func labelsShareTheOBYWRoot() {
            let labels = NetKitQueueLabel.allCases.map(\.label)
            #expect(labels.allSatisfy { $0.hasPrefix("one.obyw.netkit.") })
            #expect(Set(labels).count == labels.count)
        }

        @Test("a queue made from a case carries that case's label")
        func queueCarriesItsLabel() {
            #expect(NetKitQueueLabel.dlnaBrowser.makeQueue().label == "one.obyw.netkit.dlna.browser")
        }
    }
}
#endif
