# OpenSpec: Structured Extraction

## Overview
Markdown-formatted PDF extraction with layout preservation using the unpdf backend.

## Capability: Structured Markdown Extraction

### Functional Requirements

#### RQ-STR-001: Markdown Output
StructuredEngine **SHALL** produce valid Markdown formatted output that preserves document layout.

#### RQ-STR-002: Dual Output
StructuredEngine **MUST** provide both:
- Formatted markdown content in `ExtractionResult.markdown`
- Plain text content in `ExtractionResult.text`

#### RQ-STR-003: Parallel Support
StructuredEngine **SHALL** support parallel page processing when enabled.

#### RQ-STR-004: Page Range Handling
StructuredEngine **MUST** respect page range configuration parameters.

#### RQ-STR-005: Error Conversion
All `unpdf` library errors **SHALL** be converted to `SuperWrapperError::Unpdf` variants.

---

## Success Scenarios

### Scenario STR-001: Markdown Extraction
**GIVEN** A PDF document with formatted text
**WHEN** Extracted using StructuredEngine
**THEN** `result.markdown` contains formatted Markdown
**AND** Headers, lists, and paragraphs are preserved
**AND** Text flow matches document layout

### Scenario STR-002: Sequential Extraction
**GIVEN** Multi-page document
**WHEN** `parallel: false` in configuration
**THEN** Pages are processed sequentially
**AND** Markdown output is complete and formatted

### Scenario STR-003: Parallel Extraction
**GIVEN** Multi-page document
**WHEN** `parallel: true` in configuration
**THEN** Pages are processed in parallel
**AND** Result content is identical to sequential extraction

### Scenario STR-004: Page Range Extraction
**GIVEN** 10-page document
**WHEN** Page range `2..=7` is specified
**THEN** Only pages 3-8 are included in output
**AND** Markdown formatting is preserved for extracted pages

---

## Edge Case Scenarios

### Scenario STR-EC-001: Empty Document
**GIVEN** PDF with no text content
**WHEN** Extracted with StructuredEngine
**THEN** Empty markdown and text fields are returned
**AND** No error is generated

### Scenario STR-EC-002: Image-Only PDF
**GIVEN** PDF containing only scanned images
**WHEN** Extracted with StructuredEngine
**THEN** Empty text/markdown is returned
**AND** Operation completes successfully

### Scenario STR-EC-003: Complex Layout
**GIVEN** PDF with multi-column layout
**WHEN** Extracted with StructuredEngine
**THEN** Content is ordered logically
**AND** Markdown structure reflects reading order

### Scenario STR-EC-004: Corrupted Page
**GIVEN** PDF with one corrupted page
**WHEN** Extracted with StructuredEngine
**THEN** Good pages are extracted successfully
**AND** Corrupted page produces appropriate error

---

## Technical Constraints

### Dependencies
- Requires `structured` Cargo feature
- Depends on `unpdf` crate
- No system library dependencies

### Performance
- Typical latency: 20-50ms per page
- Memory usage: ~10MB per 100 pages
- Parallel processing scales linearly with CPU cores

### Output Constraints
- Markdown output is UTF-8 encoded
- No embedded images in markdown output
- Page breaks are represented as double newlines

---

## Implementation Location
`crates/superwrapper-pdf/src/engine/structured.rs`
