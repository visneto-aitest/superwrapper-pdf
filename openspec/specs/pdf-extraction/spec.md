# OpenSpec: PDF Extraction Capability

## Overview
Unified PDF content extraction system providing three specialized extraction engines behind a single consistent interface.

## Capability: PDF Extraction

### Functional Requirements

#### RQ-001: Engine Selection
The system **SHALL** support three distinct extraction engines:
- FastEngine (plain text, maximum speed)
- StructuredEngine (markdown format, layout preservation)
- VisualEngine (image rendering + text extraction)

#### RQ-002: Unified Interface
All engines **MUST** implement the `PdfEngine` trait contract, ensuring interchangeable usage.

#### RQ-003: Feature Gating
Engines **SHALL** be feature-gated through Cargo features to minimize binary size:
- `fast`: Always included (no optional dependencies)
- `structured`: Requires `unpdf` dependency
- `visual`: Requires `pdfium-render` and system pdfium library

#### RQ-004: Thread Safety
All engine implementations **MUST** implement `Send` + `Sync` traits for safe cross-thread sharing.

#### RQ-005: Parallel Processing
The system **SHALL** support parallel page processing using Rayon when enabled.

#### RQ-006: Async Support
The system **SHALL** provide async/await integration with Tokio runtime when the `async` feature is enabled.

#### RQ-007: Password Protection
The system **MUST** support extraction from password-protected PDFs.

#### RQ-008: Page Range Selection
The system **SHALL** support extracting specific page ranges instead of entire documents.

---

## Success Scenarios

### Scenario 1: Successful Fast Extraction
**GIVEN** A valid unencrypted PDF document exists at `/tmp/document.pdf`
**WHEN** `FastEngine.extract()` is called with default configuration
**THEN** An `ExtractionResult` is returned
**AND** The result contains plain text content
**AND** Page count matches the document's actual page count
**AND** Per-page metadata is populated

### Scenario 2: Structured Markdown Extraction
**GIVEN** A valid PDF document with formatted content
**AND** The `structured` feature is enabled
**WHEN** `StructuredEngine.extract()` is called
**THEN** The result contains valid markdown formatted content
**AND** Document layout is preserved
**AND** Plain text content is also available

### Scenario 3: Visual Image Rendering
**GIVEN** A valid PDF document
**AND** The `visual` feature is enabled
**WHEN** `VisualEngine.extract()` is called with `ExtractionMode::Visual`
**THEN** Pages are rendered to images in specified format
**AND** Text extraction is still performed
**AND** Image quality matches configured DPI setting

### Scenario 4: Parallel Processing
**GIVEN** A multi-page PDF document
**WHEN** Extraction is performed with `parallel: true`
**THEN** Extraction completes faster than sequential processing
**AND** Result content is identical to sequential extraction

### Scenario 5: Page Range Extraction
**GIVEN** A 10-page PDF document
**WHEN** Extraction is requested with page range `2..=5`
**THEN** Only pages 3-6 (1-indexed) are extracted
**AND** Total page count in result remains 10
**AND** Extracted pages maintain correct numbering

---

## Edge Case Scenarios

### Scenario EC-001: Encrypted Document Without Password
**GIVEN** A password-protected PDF document
**WHEN** Extraction is attempted without providing a password
**THEN** `SuperWrapperError::Encrypted` is returned
**AND** The error includes the document path

### Scenario EC-002: Invalid Page Range
**GIVEN** A 5-page PDF document
**WHEN** Extraction is requested with page range `10..=15`
**THEN** `SuperWrapperError::PageOutOfRange` is returned
**AND** The error indicates requested page vs available pages

### Scenario EC-003: Corrupted PDF
**GIVEN** An invalid or corrupted PDF file
**WHEN** Extraction is attempted
**THEN** `SuperWrapperError::PdfParse` is returned
**AND** The error includes parsing failure details

### Scenario EC-004: Disabled Feature
**GIVEN** Library compiled without `visual` feature
**WHEN** `VisualEngine` is used
**THEN** `SuperWrapperError::FeatureNotEnabled` is returned
**AND** The error indicates which feature to enable

### Scenario EC-005: File Not Found
**GIVEN** No file exists at requested path
**WHEN** Extraction is attempted
**THEN** `SuperWrapperError::Io` is returned with NotFound kind

---

## Technical Constraints

### Runtime Requirements
- Rust 1.75+ (MSRV)
- Tokio 1.0+ (for async support)
- Rayon 1.0+ (for parallel processing)

### Engine Dependencies
- FastEngine: `pdf_oxide` (included by default)
- StructuredEngine: `unpdf` (requires `structured` feature)
- VisualEngine: `pdfium-render` + system PDFium library

### Compilation Constraints
- All features are additive
- No default features enable heavy dependencies
- Serde support is optional for serialization

### Performance Guarantees
- FastEngine: <10ms per page (typical)
- StructuredEngine: <50ms per page (typical)
- VisualEngine: <200ms per page at 150 DPI

---

## Implementation Location
`crates/superwrapper-pdf/src/engine/`
