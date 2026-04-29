import XCTest
@testable import SymphonyWorkflow

final class WorkflowParserTests: XCTestCase {
    func testParsesFrontMatterAndBody() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/WORKFLOW.md")
        let document = try WorkflowParser.parse(
            content: """
            ---
            name: "Composer workflow"
            enabled: true
            retries: 2
            temperature: 0.4
            agents: [codex, "claude", gemini]
            ---
            Build the feature.
            """,
            fileURL: fileURL
        )

        XCTAssertEqual(document.fileURL, fileURL)
        XCTAssertEqual(document.frontMatter?.string(for: "name"), "Composer workflow")
        XCTAssertEqual(document.frontMatter?.bool(for: "enabled"), true)
        XCTAssertEqual(document.frontMatter?["retries"], .integer(2))
        XCTAssertEqual(document.frontMatter?["temperature"], .number(0.4))
        XCTAssertEqual(document.frontMatter?.stringList(for: "agents"), ["codex", "claude", "gemini"])
        XCTAssertEqual(document.body, "Build the feature.")
    }

    func testContentWithoutFrontMatterUsesWholeBody() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/WORKFLOW.md")
        let content = "Build the feature.\n"

        let document = try WorkflowParser.parse(content: content, fileURL: fileURL)

        XCTAssertNil(document.frontMatter)
        XCTAssertEqual(document.body, content)
        XCTAssertEqual(document.content, content)
    }

    func testThrowsForUnclosedFrontMatter() {
        let fileURL = URL(fileURLWithPath: "/tmp/WORKFLOW.md")

        XCTAssertThrowsError(
            try WorkflowParser.parse(content: "---\nname: Composer\n", fileURL: fileURL)
        ) { error in
            XCTAssertEqual(error as? WorkflowParserError, .unclosedFrontMatter(fileURL: fileURL))
        }
    }

    func testThrowsForInvalidFrontMatterLine() {
        let fileURL = URL(fileURLWithPath: "/tmp/WORKFLOW.md")

        XCTAssertThrowsError(
            try WorkflowParser.parse(content: "---\nmissing separator\n---\n", fileURL: fileURL)
        ) { error in
            XCTAssertEqual(
                error as? WorkflowParserError,
                .invalidFrontMatterLine(fileURL: fileURL, line: 2, reason: "Expected key: value.")
            )
        }
    }
}
