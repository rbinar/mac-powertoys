import XCTest
@testable import MacPowerToys

// Real network and a real yt-dlp are not exercised here: downloads go through StubURLProtocol,
// and yt-dlp is covered only through its pure argument/progress functions.

/// In-process HTTP server for `URLSession`: HEAD, ranged GET, optional range-ignoring mode, slow chunks.
final class StubURLProtocol: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _data = Data()
        private var _etag = "\"v1\""
        private var _ignoreRange = false
        private var _chunkDelay: TimeInterval = 0
        private var _served = 0
        private var _ranges: [String] = []

        func configure(data: Data, etag: String = "\"v1\"", ignoreRange: Bool = false, chunkDelay: TimeInterval = 0) {
            lock.lock(); defer { lock.unlock() }
            _data = data; _etag = etag; _ignoreRange = ignoreRange; _chunkDelay = chunkDelay; _served = 0; _ranges = []
        }
        func snapshot() -> (data: Data, etag: String, ignoreRange: Bool, delay: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            return (_data, _etag, _ignoreRange, _chunkDelay)
        }
        func addServed(_ n: Int) { lock.lock(); _served += n; lock.unlock() }
        func resetServed() { lock.lock(); _served = 0; lock.unlock() }
        var served: Int { lock.lock(); defer { lock.unlock() }; return _served }
        func record(_ range: String) { lock.lock(); _ranges.append(range); lock.unlock() }
        var ranges: [String] { lock.lock(); defer { lock.unlock() }; return _ranges }
    }

    static let state = State()
    private let stopLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let config = Self.state.snapshot()
        let total = config.data.count
        guard let url = request.url else { return }
        var headers = ["Accept-Ranges": "bytes", "ETag": config.etag]

        if request.httpMethod == "HEAD" {
            headers["Content-Length"] = String(total)
            respond(url, 200, headers)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        var lower = 0
        var upper = total - 1
        var status = 200
        if let range = request.value(forHTTPHeaderField: "Range"), !config.ignoreRange {
            Self.state.record(range)
            let bounds = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-", omittingEmptySubsequences: false)
            lower = Int(bounds[0]) ?? 0
            if bounds.count > 1, let end = Int(bounds[1]) { upper = min(end, total - 1) }
            status = 206
            headers["Content-Range"] = "bytes \(lower)-\(upper)/\(total)"
        }
        let body = config.data.subdata(in: lower..<(upper + 1))
        headers["Content-Length"] = String(body.count)
        respond(url, status, headers)

        DispatchQueue.global().async {
            var offset = 0
            while offset < body.count {
                self.stopLock.lock(); let isStopped = self.stopped; self.stopLock.unlock()
                if isStopped { return }
                let end = min(offset + 4096, body.count)
                self.client?.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
                Self.state.addServed(end - offset)
                offset = end
                if config.delay > 0 { Thread.sleep(forTimeInterval: config.delay) }
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopLock.lock(); stopped = true; stopLock.unlock()
    }

    private func respond(_ url: URL, _ status: Int, _ headers: [String: String]) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}

@MainActor
final class DownloadManagerModelTests: XCTestCase {
    private static let defaultsKeys = ["downloadManager.connections", "downloadManager.saveFolder", "downloadManager.watchClipboard"]
    private var folder: URL!
    private var storeURL: URL!
    private var models: [DownloadManagerModel] = []

    override func setUp() {
        super.setUp()
        Self.defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("dm-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("store/downloads.json")
        StubURLProtocol.state.configure(data: Data())
    }

    override func tearDown() {
        models.forEach { $0.stopMonitoring() }
        models = []
        try? FileManager.default.removeItem(at: folder)
        Self.defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: helpers

    private func makeModel() -> DownloadManagerModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let model = DownloadManagerModel(session: URLSession(configuration: config), storeURL: storeURL)
        model.saveFolderPath = folder.path
        model.minPartSize = 1
        models.append(model)
        return model
    }

    private func payload(_ count: Int, salt: Int = 0) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8) &+ salt) })
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    private func finish(_ model: DownloadManagerModel, expecting data: Data, file: StaticString = #filePath, line: UInt = #line) async {
        let done = await wait { model.tasks.first?.state == .completed || model.tasks.first?.state == .failed }
        XCTAssertTrue(done, "download did not finish", file: file, line: line)
        XCTAssertEqual(model.tasks.first?.state, .completed, model.tasks.first?.message ?? "", file: file, line: line)
        guard let item = model.tasks.first else { return }
        XCTAssertEqual(try? Data(contentsOf: URL(fileURLWithPath: item.finalPath)), data, file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.tempPath), file: file, line: line)
    }

    private func start(_ model: DownloadManagerModel, path: String = "/files/data.bin") {
        model.urlText = "https://example.test\(path)"
        model.addFromInput()
    }

    // MARK: pure functions

    func testValidURLAcceptsOnlyHttps() {
        XCTAssertNotNil(DownloadManagerModel.validURL(" https://a.test/x "))
        XCTAssertNil(DownloadManagerModel.validURL("http://a.test/x"))
        XCTAssertNil(DownloadManagerModel.validURL("ftp://a.test/x"))
        XCTAssertNil(DownloadManagerModel.validURL("file:///etc/passwd"))
        XCTAssertNil(DownloadManagerModel.validURL("javascript:alert(1)"))
        XCTAssertNil(DownloadManagerModel.validURL("https://"))
        XCTAssertNil(DownloadManagerModel.validURL("https://a.test/a b"))
        XCTAssertNil(DownloadManagerModel.validURL("not a url"))
    }

    func testPlanPartsCoversEveryByteOnceInOrder() {
        for (total, wanted) in [(10_000_000, 4), (10_000_001, 3), (7, 4), (100, 8)] as [(Int64, Int)] {
            let parts = DownloadManagerModel.planParts(totalLength: total, connections: wanted, minPartSize: 1)
            XCTAssertEqual(parts.first?.start, 0)
            XCTAssertEqual(parts.last?.end, total - 1)
            XCTAssertEqual(parts.count, Int(min(Int64(wanted), total)))
            for (a, b) in zip(parts, parts.dropFirst()) { XCTAssertEqual(a.end! + 1, b.start) }
            XCTAssertEqual(parts.reduce(0) { $0 + $1.length! }, total)
        }
    }

    func testPlanPartsRespectsLimitsAndMinimumSize() {
        XCTAssertEqual(DownloadManagerModel.planParts(totalLength: 100, connections: 50, minPartSize: 1).count, 8)
        XCTAssertEqual(DownloadManagerModel.planParts(totalLength: 100, connections: 0, minPartSize: 1).count, 1)
        XCTAssertEqual(DownloadManagerModel.planParts(totalLength: 500_000, connections: 4).count, 1)
        XCTAssertEqual(DownloadManagerModel.planParts(totalLength: 0, connections: 4).first?.length, 0)
    }

    func testPlanResumeContinuesOnlyIncompleteParts() {
        let parts = [DownloadPart(start: 0, end: 99, received: 100), DownloadPart(start: 100, end: 199, received: 40)]
        let v = DownloadValidators(etag: "a", lastModified: "m", length: 200)
        XCTAssertEqual(DownloadManagerModel.planResume(parts: parts, saved: v, current: v, serverAcceptsRanges: true),
                       .resume(remaining: [1]))
    }

    func testPlanResumeRestartsWhenTheFileChangedOrRangesAreGone() {
        let parts = [DownloadPart(start: 0, end: 99, received: 50)]
        let saved = DownloadValidators(etag: "a", lastModified: "m", length: 100)
        func plan(_ current: DownloadValidators, ranges: Bool = true) -> DownloadResumePlan {
            DownloadManagerModel.planResume(parts: parts, saved: saved, current: current, serverAcceptsRanges: ranges)
        }
        var changed = saved; changed.etag = "b"
        guard case .restart = plan(changed) else { return XCTFail("etag change must restart") }
        changed = saved; changed.lastModified = "n"
        guard case .restart = plan(changed) else { return XCTFail("last-modified change must restart") }
        changed = saved; changed.length = 101
        guard case .restart = plan(changed) else { return XCTFail("length change must restart") }
        guard case .restart = plan(saved, ranges: false) else { return XCTFail("lost ranges must restart") }
        XCTAssertEqual(plan(DownloadValidators(etag: nil, lastModified: nil, length: nil)), .resume(remaining: [0]))
    }

    func testFileNameFromContentDispositionOrURLIsAlwaysBare() {
        let url = URL(string: "https://a.test/dir/report%20final.pdf?x=1")!
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: nil, url: url), "report final.pdf")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: "attachment; filename=\"a.zip\"", url: url), "a.zip")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: "attachment; filename=\"a.zip\"; filename*=UTF-8''%C3%BCber.zip", url: url), "über.zip")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: "attachment; filename=\"../../etc/passwd\"", url: url), "passwd")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: "attachment; filename=\"..\\..\\evil.sh\"", url: url), "evil.sh")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: "attachment; filename=\"..\"", url: url), "report final.pdf")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: nil, url: URL(string: "https://a.test/")!), "download")
        XCTAssertEqual(DownloadManagerModel.chooseFileName(contentDisposition: nil, url: URL(string: "https://a.test/%2E%2E%2Fx")!), "x")
    }

    func testUniqueFileNameNeverReturnsAnExistingName() {
        let taken: Set<String> = ["a.zip", "a (1).zip", "noext"]
        XCTAssertEqual(DownloadManagerModel.uniqueFileName("b.zip") { taken.contains($0) }, "b.zip")
        XCTAssertEqual(DownloadManagerModel.uniqueFileName("a.zip") { taken.contains($0) }, "a (2).zip")
        XCTAssertEqual(DownloadManagerModel.uniqueFileName("noext") { taken.contains($0) }, "noext (1)")
    }

    func testParsesYtDlpProgressAndDestination() {
        let line = DownloadManagerModel.parseYtDlpProgress("[download]  45.3% of ~  10.00MiB at    1.20MiB/s ETA 00:05")
        XCTAssertEqual(line?.fraction ?? 0, 0.453, accuracy: 0.0001)
        XCTAssertEqual(line?.speed, "1.20MiB/s")
        XCTAssertEqual(DownloadManagerModel.parseYtDlpProgress("[download] 100% of 3.00MiB in 00:02")?.fraction, 1)
        XCTAssertNil(DownloadManagerModel.parseYtDlpProgress("[info] Downloading 1 format"))
        XCTAssertEqual(DownloadManagerModel.parseYtDlpDestination("[download] Destination: /tmp/My Video.mp4"), "/tmp/My Video.mp4")
        XCTAssertEqual(DownloadManagerModel.parseYtDlpDestination("[Merger] Merging formats into \"/tmp/v.mkv\""), "/tmp/v.mkv")
        XCTAssertNil(DownloadManagerModel.parseYtDlpDestination("[download]  10.0% of 1MiB"))
    }

    func testYtDlpArgumentsPassTheURLAfterDoubleDash() {
        let args = DownloadManagerModel.ytDlpArguments(url: "https://v.test/watch?v=--x", folder: "/tmp/100%", ffmpegPath: "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(Array(args.suffix(2)), ["--", "https://v.test/watch?v=--x"])
        XCTAssertTrue(args.contains("--no-overwrites"))
        XCTAssertEqual(args[args.firstIndex(of: "--ffmpeg-location")! + 1], "/opt/homebrew/bin/ffmpeg")
        XCTAssertTrue(args[args.firstIndex(of: "-o")! + 1].hasPrefix("/tmp/100%%/"))
        XCTAssertFalse(DownloadManagerModel.ytDlpArguments(url: "u", folder: "/t", ffmpegPath: nil).contains("--ffmpeg-location"))
    }

    func testToolDetectionTakesTheFirstExistingCandidate() {
        XCTAssertEqual(DownloadManagerModel.firstExisting(["/a", "/b"]) { $0 == "/b" }, "/b")
        XCTAssertNil(DownloadManagerModel.firstExisting(["/a", "/b"]) { _ in false })
    }

    // MARK: persistence

    func testPersistedStateRoundTripAndUnfinishedDownloadsComeBackPaused() {
        var running = DownloadItem(id: UUID(), url: "https://a.test/f.bin", isVideo: false, folderPath: folder.path,
                                   fileName: "f.bin", tempName: ".f.bin.part", state: .downloading)
        running.totalLength = 100
        running.parts = [DownloadPart(start: 0, end: 49, received: 50), DownloadPart(start: 50, end: 99, received: 10)]
        running.validators = DownloadValidators(etag: "\"x\"", lastModified: "m", length: 100)
        let finished = DownloadItem(id: UUID(), url: "https://a.test/g.bin", isVideo: false, folderPath: folder.path,
                                    fileName: "g.bin", state: .completed)
        DownloadManagerModel.save([running, finished], to: storeURL)
        XCTAssertEqual(DownloadManagerModel.load(from: storeURL), [running, finished])

        let model = makeModel()
        XCTAssertEqual(model.tasks.map(\.state), [.paused, .completed])
        XCTAssertEqual(model.tasks[0].parts, running.parts)
        XCTAssertEqual(model.tasks[0].validators, running.validators)
    }

    // MARK: transfers

    func testParallelRangedDownloadProducesExactBytes() async {
        let data = payload(300_001)
        StubURLProtocol.state.configure(data: data)
        let model = makeModel()
        start(model)
        await finish(model, expecting: data)
        XCTAssertEqual(model.tasks.first?.parts.count, 4)
        XCTAssertEqual(StubURLProtocol.state.ranges.count, 4)
    }

    func testExistingFileIsNeverOverwritten() async {
        let data = payload(5_000)
        StubURLProtocol.state.configure(data: data)
        let existing = Data("keep me".utf8)
        try? existing.write(to: folder.appendingPathComponent("data.bin"))
        let model = makeModel()
        start(model)
        await finish(model, expecting: data)
        XCTAssertEqual(model.tasks.first?.fileName, "data (1).bin")
        XCTAssertEqual(try? Data(contentsOf: folder.appendingPathComponent("data.bin")), existing)
    }

    func testPauseThenResumeRequestsOnlyTheRemainingBytesAndKeepsExactBytes() async {
        let data = payload(400_000)
        StubURLProtocol.state.configure(data: data, chunkDelay: 0.02)
        let model = makeModel()
        start(model)
        let progressed = await wait { (model.tasks.first?.receivedBytes ?? 0) > 0 }
        XCTAssertTrue(progressed)
        model.pause(model.tasks[0].id)
        XCTAssertEqual(model.tasks.first?.state, .paused)
        XCTAssertLessThan(model.tasks[0].receivedBytes, Int64(data.count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.tasks[0].tempPath))

        try? await Task.sleep(nanoseconds: 200_000_000)
        StubURLProtocol.state.configure(data: data)
        model.resume(model.tasks[0].id)
        await finish(model, expecting: data)
        XCTAssertLessThan(StubURLProtocol.state.served, data.count, "resume must not refetch the finished bytes")
    }

    func testDownloadSurvivesAppRestart() async {
        let data = payload(400_000)
        StubURLProtocol.state.configure(data: data, chunkDelay: 0.02)
        let first = makeModel()
        start(first)
        _ = await wait { (first.tasks.first?.receivedBytes ?? 0) > 0 }
        first.stopMonitoring()
        try? await Task.sleep(nanoseconds: 200_000_000)

        StubURLProtocol.state.configure(data: data)
        let second = makeModel()
        XCTAssertEqual(second.tasks.count, 1)
        XCTAssertEqual(second.tasks[0].state, .paused)
        XCTAssertGreaterThan(second.tasks[0].receivedBytes, 0)
        second.resume(second.tasks[0].id)
        await finish(second, expecting: data)
    }

    func testServerThatIgnoresRangesFallsBackToOneConnectionWithoutCorruption() async {
        let data = payload(200_000)
        StubURLProtocol.state.configure(data: data, ignoreRange: true)
        let model = makeModel()
        start(model)
        await finish(model, expecting: data)
        XCTAssertEqual(model.tasks.first?.parts.count, 1)
        XCTAssertTrue(model.tasks.first?.message?.contains("ignored") ?? false)
    }

    func testChangedFileOnResumeRestartsAndSaysSo() async {
        let old = payload(400_000)
        let new = payload(400_000, salt: 7)
        StubURLProtocol.state.configure(data: old, chunkDelay: 0.02)
        let model = makeModel()
        start(model)
        _ = await wait { (model.tasks.first?.receivedBytes ?? 0) > 0 }
        model.pause(model.tasks[0].id)
        try? await Task.sleep(nanoseconds: 200_000_000)

        StubURLProtocol.state.configure(data: new, etag: "\"v2\"")
        model.resume(model.tasks[0].id)
        await finish(model, expecting: new)
        XCTAssertTrue(model.tasks.first?.message?.contains("changed") ?? false)
    }

    func testCancelRemovesThePartialFileAndTheTask() async {
        StubURLProtocol.state.configure(data: payload(400_000), chunkDelay: 0.02)
        let model = makeModel()
        start(model)
        _ = await wait { (model.tasks.first?.receivedBytes ?? 0) > 0 }
        let temp = model.tasks[0].tempPath
        model.cancel(model.tasks[0].id)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp))
    }

    func testCancelBeforeTheProbeEndsLeavesTheSaveFolderAlone() throws {
        StubURLProtocol.state.configure(data: payload(1000))
        let model = makeModel()
        let keep = folder.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keep)
        start(model) // tempName is still empty
        model.cancel(model.tasks[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    func testPartialPathsNeverIncludeTheSaveFolder() {
        let video = DownloadItem(id: UUID(), url: "https://a.b/c", isVideo: true, folderPath: "/tmp/d", fileName: "f.mp4", state: .downloading)
        XCTAssertEqual(video.partialPaths, ["/tmp/d/f.mp4.part"])
        var file = DownloadItem(id: UUID(), url: "https://a.b/c", isVideo: false, folderPath: "/tmp/d", fileName: "c", state: .downloading)
        XCTAssertEqual(file.partialPaths, [])
        file.tempName = ".c.mpdownload"
        XCTAssertEqual(file.partialPaths, ["/tmp/d/.c.mpdownload"])
    }

    func testRejectsNonHttpInputWithoutStartingAnything() {
        let model = makeModel()
        model.urlText = "ftp://example.test/x"
        model.addFromInput()
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertNotNil(model.inputError)
    }
}
