import XCTest
@testable import MacPowerToys

// Real paste (focus switch + ⌘V into another app), the global hotkey and the palette UI are not tested here.
@MainActor
final class AdvancedPasteModelTests: XCTestCase {
    private let key = "advancedPaste.isEnabled"
    private var saved: Any?

    // Case transforms take the locale explicitly: "en" for English text, "tr" for Turkish text.
    private let en = Locale(identifier: "en_US")
    private let tr = Locale(identifier: "tr_TR")

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        super.tearDown()
    }

    private func md(_ html: String) -> String { AdvancedPasteModel.markdown(fromHTML: html) }

    // MARK: - JSON

    func testMinifiedJSON() {
        XCTAssertEqual(AdvancedPasteModel.minifiedJSON("{ \"b\": 1,\n \"a\": [1, 2] }"), "{\"a\":[1,2],\"b\":1}")
    }

    func testPrettyJSONIsIndentedMultiline() {
        let out = AdvancedPasteModel.prettyJSON("{\"b\":1,\"a\":[1,2]}")
        XCTAssertEqual(out, "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1\n}")
    }

    func testInvalidJSONIsNil() {
        XCTAssertNil(AdvancedPasteModel.prettyJSON("{\"a\": }"))
        XCTAssertNil(AdvancedPasteModel.minifiedJSON("not json"))
        XCTAssertNil(AdvancedPasteModel.prettyJSON("42"))
    }

    func testEmptyJSONIsNil() {
        XCTAssertNil(AdvancedPasteModel.prettyJSON(""))
        XCTAssertNil(AdvancedPasteModel.minifiedJSON("   "))
    }

    // MARK: - Case

    func testUppercaseAndLowercaseEnglish() {
        XCTAssertEqual(AdvancedPasteModel.uppercased("Hello World", locale: en), "HELLO WORLD")
        XCTAssertEqual(AdvancedPasteModel.lowercased("Hello World", locale: en), "hello world")
    }

    func testTurkishLocaleKeepsDottedAndDotlessI() {
        XCTAssertEqual(AdvancedPasteModel.uppercased("istanbul ışık", locale: tr), "İSTANBUL IŞIK")
        XCTAssertEqual(AdvancedPasteModel.lowercased("İSTANBUL IŞIK", locale: tr), "istanbul ışık")
    }

    func testLowercasingCapitalDottedIHasNoCombiningDotInAnyLocale() {
        for locale in [en, tr] {
            let out = AdvancedPasteModel.lowercased("İzmir", locale: locale)
            XCTAssertEqual(out, "izmir")
            XCTAssertFalse(out.unicodeScalars.contains("\u{307}"))
        }
    }

    func testTitleCase() {
        XCTAssertEqual(AdvancedPasteModel.titleCased("hELLO  wORLD\nsecond line", locale: en), "Hello  World\nSecond Line")
        XCTAssertEqual(AdvancedPasteModel.titleCased("istanbul İZMİR ırmak", locale: tr), "İstanbul İzmir Irmak")
    }

    // MARK: - Markdown

    func testMarkdownHeadingsEmphasisAndParagraphs() {
        let html = "<h1>Title</h1><p>Some <b>bold</b> and <em>italic</em> text.</p><h2>Sub</h2><p>Next</p>"
        XCTAssertEqual(md(html), "# Title\n\nSome **bold** and *italic* text.\n\n## Sub\n\nNext")
    }

    func testMarkdownNestedListWithLink() {
        let html = """
        <ul>
          <li>One <a href="https://example.com/a?x=1&amp;y=2">link</a></li>
          <li>Two
            <ol>
              <li>Inner a</li>
              <li>Inner b</li>
            </ol>
          </li>
          <li>Three</li>
        </ul>
        <p>After</p>
        """
        XCTAssertEqual(md(html), "- One [link](https://example.com/a?x=1&y=2)\n- Two\n  1. Inner a\n  2. Inner b\n- Three\n\nAfter")
    }

    func testMarkdownDropsUnknownTagsStylesAndDecodesEntities() {
        let html = "<html><head><style>p{color:red}</style></head><body><span>a &lt; b &amp;&amp; c&nbsp;d</span><br>next</body></html>"
        XCTAssertEqual(md(html), "a < b && c d\nnext")
    }

    func testMarkdownKeepsTurkishCharacters() {
        XCTAssertEqual(md("<p><strong>İstanbul</strong> ışık</p>"), "**İstanbul** ışık")
    }

    // MARK: - apply (availability)

    func testApplyDisablesMarkdownWithoutHTML() {
        let source = PasteSource(text: "hello", html: nil)
        XCTAssertNil(AdvancedPasteModel.apply(.markdown, to: source, locale: en))
        XCTAssertEqual(AdvancedPasteModel.apply(.plainText, to: source, locale: en), "hello")
    }

    func testApplyUsesHTMLForMarkdown() {
        let source = PasteSource(text: "Hi", html: "<b>Hi</b>")
        XCTAssertEqual(AdvancedPasteModel.apply(.markdown, to: source, locale: en), "**Hi**")
    }

    func testApplyDisablesJSONTransformsForNonJSON() {
        let source = PasteSource(text: "plain words", html: nil)
        XCTAssertNil(AdvancedPasteModel.apply(.prettyJSON, to: source, locale: en))
        XCTAssertNil(AdvancedPasteModel.apply(.minifiedJSON, to: source, locale: en))
        XCTAssertEqual(AdvancedPasteModel.apply(.titleCase, to: source, locale: en), "Plain Words")
    }

    func testApplyWithEmptyOrMissingTextIsNilForEveryTransform() {
        for source in [PasteSource(text: nil, html: "<b>x</b>"), PasteSource(text: "", html: nil)] {
            for transform in PasteTransform.allCases {
                XCTAssertNil(AdvancedPasteModel.apply(transform, to: source, locale: en))
            }
        }
    }

    // MARK: - Model

    func testPasteKeyEventsAreCommandV() {
        let events = AdvancedPasteModel.pasteKeyEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskCommand) && $0.getIntegerValueField(.keyboardEventKeycode) == 9 })
    }

    func testEnabledFlagPersists() {
        let model = AdvancedPasteModel()
        XCTAssertFalse(model.isEnabled)
        model.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        model.isEnabled = false
        model.stopMonitoring()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }
}
