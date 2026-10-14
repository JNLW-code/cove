import Foundation

/// Claude API list prices in dollars per million tokens. The 1-hour cache write costs more than the 5-minute one.
/// Checked against Claude Code's own `cost-state` totals (14 Oct 2026): Fable 5.1 matches to the cent, the others within a few %.
struct ModelRates: Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double

    /// Longest prefix wins. Model ids look like "claude-opus-5-5", sometimes with "[1m]" or a date on the end.
    private static let table: [(prefix: String, rates: ModelRates)] = [
        ("fable-5",   ModelRates(input: 10,   output: 50,  cacheRead: 0.25, cacheWrite5m: 12.5,  cacheWrite1h: 20)),
        ("mythos-5",  ModelRates(input: 10,   output: 50,  cacheRead: 0.25, cacheWrite5m: 12.5,  cacheWrite1h: 20)),
        ("opus-5-5",  ModelRates(input: 4,    output: 20,  cacheRead: 0.20, cacheWrite5m: 5,     cacheWrite1h: 8)),
        ("opus-5",    ModelRates(input: 5,    output: 25,  cacheRead: 0.50, cacheWrite5m: 6.25,  cacheWrite1h: 10)),
        ("opus-4",    ModelRates(input: 5,    output: 25,  cacheRead: 0.50, cacheWrite5m: 6.25,  cacheWrite1h: 10)),
        ("sonnet-5",  ModelRates(input: 2,    output: 10,  cacheRead: 0.20, cacheWrite5m: 2.5,   cacheWrite1h: 4)),
        ("sonnet-4",  ModelRates(input: 3,    output: 15,  cacheRead: 0.30, cacheWrite5m: 3.75,  cacheWrite1h: 6)),
        ("haiku-5",   ModelRates(input: 0.1,  output: 0.5, cacheRead: 0.01, cacheWrite5m: 0.125, cacheWrite1h: 0.2)),
        ("haiku-4",   ModelRates(input: 1,    output: 5,   cacheRead: 0.10, cacheWrite5m: 1.25,  cacheWrite1h: 2)),
    ]

    static func lookup(_ model: String) -> ModelRates? {
        var name = model.lowercased()
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        return table.filter { name.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.rates
    }
}

/// What one session has used so far: dollars from every assistant message in its transcript (subagents included)
/// and the number of prompts James has sent it.
struct UsageTotals: Sendable, Equatable {
    var costUSD: Double = 0
    var turns: Int = 0
    /// A model the price table does not know was seen; its tokens are not in `costUSD`.
    var unknownModel: String?
}

/// Reads Claude Code transcripts (`~/.claude/projects/…/<session>.jsonl` and `<session>/subagents/*.jsonl`) a bit at a time:
/// it remembers how far each file was read, so a refresh costs only the bytes written since the last one.
/// Off the main thread; nothing here is ever logged (the transcript holds the whole conversation).
actor TranscriptReader {
    private struct FileState {
        var offset: UInt64 = 0
        var remainder = Data()
        var lastMessageID = ""
    }

    private var files: [String: FileState] = [:]
    private var totals: [String: UsageTotals] = [:]
    private var sessionFiles: [String: Set<String>] = [:]

    private static let chunk = 4 * 1024 * 1024
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)
    private static let promptMarker = Data("\"promptIndex\":".utf8)

    func refresh(session: String, transcript: String) -> UsageTotals {
        var t = totals[session] ?? UsageTotals()
        var paths = [transcript]
        let agentsDir = (transcript as NSString).deletingPathExtension + "/subagents"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: agentsDir) {
            paths += names.filter { $0.hasSuffix(".jsonl") }.sorted().map { agentsDir + "/" + $0 }
        }
        for path in paths {
            sessionFiles[session, default: []].insert(path)
            read(path, into: &t)
        }
        totals[session] = t
        return t
    }

    func forget(session: String) {
        for path in sessionFiles[session] ?? [] { files[path] = nil }
        sessionFiles[session] = nil
        totals[session] = nil
    }

    private func read(_ path: String, into t: inout UsageTotals) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        var state = files[path] ?? FileState()
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = FileState() }   // rewritten from the start: read it again
        guard size > state.offset, (try? handle.seek(toOffset: state.offset)) != nil else { return }
        while let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty {
            state.offset += UInt64(data.count)
            state.remainder.append(data)
            var start = state.remainder.startIndex
            while let newline = state.remainder[start...].firstIndex(of: 0x0A) {
                process(state.remainder[start..<newline], state: &state, into: &t)
                start = newline + 1
            }
            state.remainder = Data(state.remainder[start...])
        }
        files[path] = state
    }

    private func process(_ line: Data, state: inout FileState, into t: inout UsageTotals) {
        if line.range(of: Self.promptMarker) != nil, let index = Self.promptIndex(in: line) { t.turns = max(t.turns, index) }
        guard line.range(of: Self.assistantMarker) != nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }
        // Streaming writes one row per content block, all with the same message id and the same usage: count it once.
        let id = (message["id"] as? String) ?? ""
        if !id.isEmpty, id == state.lastMessageID { return }
        state.lastMessageID = id
        let model = (message["model"] as? String) ?? ""
        guard let rates = ModelRates.lookup(model) else {
            if !model.isEmpty, model != "<synthetic>" { t.unknownModel = model }
            return
        }
        func count(_ key: String, in dict: [String: Any]) -> Double { Double((dict[key] as? Int) ?? 0) }
        let creation = usage["cache_creation"] as? [String: Any]
        let write5m = creation.map { count("ephemeral_5m_input_tokens", in: $0) } ?? count("cache_creation_input_tokens", in: usage)
        let write1h = creation.map { count("ephemeral_1h_input_tokens", in: $0) } ?? 0
        t.costUSD += (count("input_tokens", in: usage) * rates.input
                      + count("output_tokens", in: usage) * rates.output
                      + count("cache_read_input_tokens", in: usage) * rates.cacheRead
                      + write5m * rates.cacheWrite5m
                      + write1h * rates.cacheWrite1h) / 1_000_000
    }

    /// The number after the last `"promptIndex":` in the line, without parsing the whole (possibly huge) row.
    private static func promptIndex(in line: Data) -> Int? {
        guard let range = line.range(of: promptMarker, options: [.backwards]) else { return nil }
        var value = 0, seen = false
        for byte in line[range.upperBound...] {
            if byte == 0x20 { continue }
            guard byte >= 0x30, byte <= 0x39 else { break }
            value = value * 10 + Int(byte - 0x30); seen = true
        }
        return seen ? value : nil
    }
}

/// "$0.42", "$3.20", "$87".
func costText(_ dollars: Double) -> String {
    dollars < 10 ? String(format: "$%.2f", dollars) : "$\(Int(dollars.rounded()))"
}
