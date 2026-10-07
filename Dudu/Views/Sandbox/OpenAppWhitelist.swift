import Foundation

// MARK: - D25 · OpenAppWhitelist
//
// Swift port of openmuse/apps/mobile/src/openapp/whitelist.ts — the
// URL-scheme whitelist ("light control" / 轻控制).
//
// "AI 只做决策不猜界面" (the AI decides, never guesses interfaces):
// only the fixed action paths listed here may be opened. There is no
// "open this arbitrary URL" — an unknown entry id is rejected, and every
// template slot is declared with required/optional up front.
//
// Schemes below are the documented / long-established ones (same list as
// the old whitelist): tel:/sms:/mailto: (RFC / iOS system schemes),
// https://maps.apple.com/ (Apple Map Links), iosamap://poi (AMap URI API),
// weixin://, alipay://, taobao://, openapp.jdmobile://, bilibili://,
// music://, orpheus://, qqmusic:// (the apps' long-standing schemes),
// shortcuts://x-callback-url/run-shortcut (Apple Shortcuts), bear://,
// things:///, drafts:// (canonical x-callback-url apps).
//
// Honesty notes (her research, ai-control-phone-ios-20261005):
// - Dudu CANNOT see inside the other app (iOS sandbox). Nothing here
//   detects what happens after the jump.
// - Dudu CANNOT pull itself back to the foreground. (The AI tool's
//   watchdog notification is the return path there; this user-driven list
//   is her own tap, so no watchdog is armed.)
// - x-callback x-success is NOT wired: the app has no incoming-URL
//   listener, so a callback URL would go nowhere.

enum OpenAppMode {
    /// Leaves 嘟嘟 via URL scheme.
    case jump
    /// Opens inside 嘟嘟's own in-app browser (SFSafariViewController).
    case webview
}

struct OpenAppParam: Equatable {
    let name: String
    let required: Bool
    /// Example value, shown as the field placeholder.
    let example: String
}

struct OpenAppEntry: Equatable {
    /// Stable id.
    let id: String
    /// Brand name — a proper noun, identical in every language.
    let app: String
    /// One line: when this action is the right one.
    let useWhen: String
    let mode: OpenAppMode
    /// URL template with {param} slots. Path slots are required;
    /// query slots (k={v}) are dropped when the value is empty.
    let url: String
    /// https alternative opened in the in-app browser. Absent = no web version.
    let webUrl: String?
    let params: [OpenAppParam]
    /// True when the template follows x-callback-url conventions.
    let xCallback: Bool

    var needsParams: Bool { !params.isEmpty }
}

let OPEN_APP_WHITELIST: [OpenAppEntry] = [
    OpenAppEntry(
        id: "phone-call", app: "电话",
        useWhen: "She asks you to call someone (a phone number she gave or confirmed).",
        mode: .jump, url: "tel:{phone}", webUrl: nil,
        params: [OpenAppParam(name: "phone", required: true, example: "13800138000")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "sms-send", app: "信息",
        useWhen: "She asks you to open the Messages app for a number (message body is typed by her — the scheme can't prefill it on iOS).",
        mode: .jump, url: "sms:{phone}", webUrl: nil,
        params: [OpenAppParam(name: "phone", required: true, example: "13800138000")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "mail-compose", app: "邮件",
        useWhen: "She asks you to compose an email (address required; subject/body optional).",
        mode: .jump, url: "mailto:{email}?subject={subject}&body={body}", webUrl: nil,
        params: [
            OpenAppParam(name: "email", required: true, example: "xingxing@example.com"),
            OpenAppParam(name: "subject", required: false, example: "周末计划"),
            OpenAppParam(name: "body", required: false, example: "周六去看海？"),
        ],
        xCallback: false
    ),
    OpenAppEntry(
        id: "apple-maps-search", app: "Apple 地图",
        useWhen: "She asks where something is / how to get somewhere and prefers Apple Maps.",
        mode: .jump, url: "https://maps.apple.com/?q={query}", webUrl: nil,
        params: [OpenAppParam(name: "query", required: true, example: "西湖")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "apple-maps-directions", app: "Apple 地图导航",
        useWhen: "She asks for driving directions to a place in Apple Maps.",
        mode: .jump, url: "https://maps.apple.com/?daddr={destination}&dirflg=d", webUrl: nil,
        params: [OpenAppParam(name: "destination", required: true, example: "西湖")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "amap-search", app: "高德地图",
        useWhen: "She asks where something is and prefers 高德地图 (better POI coverage in China).",
        mode: .jump, url: "iosamap://poi?sourceApplication=dudu&keywords={query}", webUrl: nil,
        params: [OpenAppParam(name: "query", required: true, example: "西湖")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "wechat-open", app: "微信",
        useWhen: "She asks you to open 微信 (e.g. to check a chat or pay). Opens the app home — you can't deep-link into a specific chat.",
        mode: .jump, url: "weixin://", webUrl: nil, params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "alipay-open", app: "支付宝",
        useWhen: "She asks you to open 支付宝 (e.g. to pay). Opens the app home.",
        mode: .jump, url: "alipay://", webUrl: nil, params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "taobao-open", app: "淘宝",
        useWhen: "She asks you to open 淘宝 to shop. Prefer the in-app web version when she just wants to browse.",
        mode: .jump, url: "taobao://", webUrl: "https://www.taobao.com", params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "jd-open", app: "京东",
        useWhen: "She asks you to open 京东 to shop. Prefer the in-app web version for browsing.",
        mode: .jump, url: "openapp.jdmobile://", webUrl: "https://www.jd.com", params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "bilibili-open", app: "哔哩哔哩",
        useWhen: "She asks you to open 哔哩哔哩. Opens the app home.",
        mode: .jump, url: "bilibili://", webUrl: "https://www.bilibili.com", params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "youtube-watch", app: "YouTube",
        useWhen: "She shares a YouTube video id and wants to watch it. Always in-app — she never leaves 嘟嘟.",
        mode: .webview, url: "https://www.youtube.com/watch?v={videoId}",
        webUrl: "https://www.youtube.com/watch?v={videoId}",
        params: [OpenAppParam(name: "videoId", required: true, example: "dQw4w9WgXcQ")],
        xCallback: false
    ),
    OpenAppEntry(
        id: "apple-music-open", app: "Apple Music",
        useWhen: "She asks you to open Apple Music.",
        mode: .jump, url: "music://", webUrl: nil, params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "netease-music-open", app: "网易云音乐",
        useWhen: "She asks you to open 网易云音乐.",
        mode: .jump, url: "orpheus://", webUrl: nil, params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "qqmusic-open", app: "QQ音乐",
        useWhen: "She asks you to open QQ音乐.",
        mode: .jump, url: "qqmusic://", webUrl: nil, params: [], xCallback: false
    ),
    OpenAppEntry(
        id: "shortcuts-run", app: "快捷指令",
        useWhen: "She asks you to run one of HER Shortcuts by name (she builds the shortcut herself; you only trigger it). This is the bridge for anything without a fixed path — the shortcut does the work, not you.",
        mode: .jump, url: "shortcuts://x-callback-url/run-shortcut?name={name}", webUrl: nil,
        params: [OpenAppParam(name: "name", required: true, example: "晚安模式")],
        xCallback: true
    ),
    OpenAppEntry(
        id: "bear-note", app: "Bear",
        useWhen: "She asks you to open a Bear note by title.",
        mode: .jump, url: "bear://x-callback-url/open-note?title={title}", webUrl: nil,
        params: [OpenAppParam(name: "title", required: true, example: "旅行清单")],
        xCallback: true
    ),
    OpenAppEntry(
        id: "things-add", app: "Things",
        useWhen: "She asks you to add a to-do to Things (title required; notes optional).",
        mode: .jump, url: "things:///x-callback-url/add?title={title}&notes={notes}", webUrl: nil,
        params: [
            OpenAppParam(name: "title", required: true, example: "买牛奶"),
            OpenAppParam(name: "notes", required: false, example: "全脂"),
        ],
        xCallback: true
    ),
    OpenAppEntry(
        id: "drafts-create", app: "Drafts",
        useWhen: "She asks you to jot something down in Drafts.",
        mode: .jump, url: "drafts://x-callback-url/create?text={text}", webUrl: nil,
        params: [OpenAppParam(name: "text", required: true, example: "灵感：给嘟嘟加个晚安模式")],
        xCallback: true
    ),
]

/// Look up a whitelist entry by id. nil = not whitelisted, never open it.
func lookupOpenAppEntry(id: String) -> OpenAppEntry? {
    let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return nil }
    return OPEN_APP_WHITELIST.first(where: { $0.id == needle })
}

enum OpenAppURLError: Error, LocalizedError {
    case missingRequiredParam(String, example: String)
    case unknownSlot(String, entry: String)
    case noWebVersion(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredParam(let name, let example):
            return "Missing required parameter \"\(name)\" (e.g. \(example))."
        case .unknownSlot(let name, let entry):
            return "Unknown template slot {\(name)} in entry \"\(entry)\"."
        case .noWebVersion(let app):
            return "\"\(app)\" has no web version."
        }
    }
}

/// Build the concrete URL from an entry template + args.
/// Path slots {name} are required and percent-encoded. Query slots (k={v})
/// are dropped when the value is empty. Throws on missing required params
/// or unknown template slots. (Port of buildEntryUrl.)
func buildEntryURL(entry: OpenAppEntry, args: [String: String]) throws -> URL {
    var values: [String: String] = [:]
    for p in entry.params {
        let v = (args[p.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if p.required, v.isEmpty {
            throw OpenAppURLError.missingRequiredParam(p.name, example: p.example)
        }
        values[p.name] = v
    }
    let template = entry.url
    let pathTemplate: String
    let queryTemplate: String?
    if let q = template.firstIndex(of: "?") {
        pathTemplate = String(template[..<q])
        queryTemplate = String(template[template.index(after: q)...])
    } else {
        pathTemplate = template
        queryTemplate = nil
    }
    var path = pathTemplate
    for match in pathTemplate.matches(of: /\{(\w+)\}/) {
        let name = String(match.1)
        guard let v = values[name] else {
            throw OpenAppURLError.unknownSlot(name, entry: entry.id)
        }
        guard !v.isEmpty else {
            throw OpenAppURLError.missingRequiredParam(name, example: name)
        }
        let encoded = v.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? v
        path = path.replacingOccurrences(of: "{\(name)}", with: encoded)
    }
    var urlString = path
    if let qt = queryTemplate {
        var kept: [String] = []
        for pair in qt.split(separator: "&") {
            let pairStr = String(pair)
            // k={v} slot form
            if let m = pairStr.wholeMatch(of: /([^=]+)=\{(\w+)\}/) {
                let v = values[String(m.2)] ?? ""
                if !v.isEmpty {
                    let encoded = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                    kept.append("\(m.1)=\(encoded)")
                }
            } else {
                kept.append(pairStr)
            }
        }
        if !kept.isEmpty { urlString += "?" + kept.joined(separator: "&") }
    }
    guard let url = URL(string: urlString) else {
        throw OpenAppURLError.unknownSlot(urlString, entry: entry.id)
    }
    return url
}

/// URL schemes declared in LSApplicationQueriesSchemes (Info.plist),
/// so canOpenURL works honestly on iOS. (Port of QUERIED_SCHEMES.)
let OPEN_APP_QUERIED_SCHEMES = [
    "tel", "sms", "mailto",
    "weixin", "alipay", "taobao", "openapp.jdmobile", "bilibili",
    "music", "orpheus", "qqmusic", "iosamap",
    "shortcuts", "bear", "things", "drafts",
]
