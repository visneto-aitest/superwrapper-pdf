# OpenSpec: Fast Text Extraction

## Overview
High-performance plain text extraction engine optimized for maximum speed and minimal memory footprint using pdf_oxide backend.

## Capability: Fast Text Extraction

### Functional Requirements

#### RQ-FAST-001: Zero Optional Dependencies
FastEngine **SHALL** have no optional dependencies and **MUST** always be available.

#### RQ-FAST-002: Maximum Speed
FastEngine **SHALL** be the fastest extraction engine implementation.

#### RQ-FAST-003: Parallel Processing
FastEngine **SHALL** support both sequential and parallel extraction modes:
- Sequential mode: `extract_sequential()`
- Parallel mode: `extract_parallel()` using pdf_oxide's parallel extractor

#### RQ-FAST-004: Page Separation
FastEngine **SHALL** separate pages with double newlines (`\n\n`) in concatenated output.

#### RQ-FAST-005: Result Consistency
FastEngine **MUST** populate both `text` and `markdown` fields with identical content.

---

## Success Scenarios

### Scenario FAST-001: Sequential Extraction
**GIVEN** Valid PDF document
**WHEN** Extracted with `parallel: false`
**THEN** All pages are processed sequentially
**AND** `ExtractionResult` contains complete text content
**AND** `result.markdown == result.text`
**AND** Page numbers are 1-indexed

### Scenario FAST-002: Parallel Extraction
**GIVEN** Multi-page PDF document
**WHEN** Extracted with `parallel: true`
**THEN** Pages are processed in parallel using Rayon
**AND** Result content is identical to sequential extraction
**AND** Extraction completes faster than sequential mode

### Scenario FAST-003: Page Range Extraction
**GIVEN** 10-page document
**WHEN** Page range `0..=4` is specified
**THEN** Only first 5 pages are extracted
**AND** Page count in result remains 10
**AND** Extracted pages maintain correct numbering

### Scenario FAST-004: Multipage Document
**GIVEN** 3-page test document
**WHEN** Extracted with default configuration
**THEN** Result contains 3 PageInfo entries
**AND** Page numbers are 1, 2, 3 respectively
**AND** Each page's char_count matches text length

---

## Edge Case Scenarios

### Scenario FAST-EC-001: Single Page Document
**GIVEN** 1-page PDF document
**WHEN** Extracted with any configuration
**THEN** No trailing double newline is added
**AND** Result contains exactly one PageInfo entry

### Scenario FAST-EC-002: Empty Page Range
**GIVEN** Page range that selects no pages
**WHEN** Extraction is performed
**THEN** Empty text/markdown is returned
**AND** Page count still reflects actual document length
**AND** No error is generated

### Scenario FAST-EC-003: Minimal PDF
**GIVEN** Smallest valid PDF (1 page, minimal content)
**WHEN** Extracted with FastEngine
**THEN** Extraction succeeds
**AND** Content is correctly extracted
**AND** Operation completes in <10ms

### Scenario FAST-EC-004: Large Document
**GIVEN** Document with 1000+ pages
**WHEN** Extracted with parallel mode
**THEN** Memory usage remains bounded
**AND** Extraction scales linearly with CPU cores
**AND** No out-of-memory errors occur

---

## Technical Constraints

### Performance Guarantees
- **Typical Latency**: <10ms per page
- **Memory Footprint**: <1MB per 100 pages
- **Throughput**: >100 pages/second (sequential)
- **Parallel Speedup**: ~0.7x per additional core

### Implementation Constraints
- No heap allocations in hot path
- Zero-copy text extraction where possible
- pdf_oxide backend provides optimized parsing
- No formatting or layout analysis performed

### Output Limitations
- Plain text only (no formatting preserved)
- Text order may not match visual layout
- No image extraction
- No metadata extraction beyond page count

---

## Implementation Location
`crates/superwrapper-pdf/src/engine/fast.rs`
