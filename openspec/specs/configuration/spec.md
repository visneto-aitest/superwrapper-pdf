# OpenSpec: Extraction Configuration

## Overview
Configuration system for controlling PDF extraction behavior across all engine implementations.

## Capability: Extraction Configuration

### Functional Requirements

#### RQ-CFG-001: Core Configuration Structure
The system **SHALL** provide an `ExtractionConfig` struct with these fields:
- `mode: ExtractionMode` - Engine selection and engine-specific options
- `page_range: Option<RangeInclusive<u32>>` - Page range to extract
- `password: Option<String>` - Password for encrypted documents
- `parallel: bool` - Enable/disable parallel processing

#### RQ-CFG-002: Extraction Mode Enumeration
The system **SHALL** define an `ExtractionMode` enum with variants:
- `Fast` - High-speed plain text extraction
- `Structured` - Markdown formatted extraction
- `Visual { dpi: u32, format: ImageFormat }` - Image rendering options

#### RQ-CFG-003: Image Format Configuration
The system **SHALL** support image output formats:
- `Png` - Lossless PNG format
- `Jpeg(u8)` - JPEG with quality parameter (0-100)

#### RQ-CFG-004: Default Values
All configuration fields **SHALL** have sensible defaults:
- `mode: ExtractionMode::Fast`
- `page_range: None` (extract all pages)
- `password: None`
- `parallel: false`

#### RQ-CFG-005: Page Range Semantics
Page ranges **MUST** be 0-indexed inclusive ranges.

---

## Success Scenarios

### Scenario CFG-001: Default Configuration
**GIVEN** `ExtractionConfig::default()`
**WHEN** Used with any engine
**THEN** Engine uses Fast mode
**AND** All pages are extracted
**AND** Sequential processing is used
**AND** No password is provided

### Scenario CFG-002: Visual Mode Configuration
**GIVEN** `ExtractionMode::Visual { dpi: 300, format: ImageFormat::Jpeg(80) }`
**WHEN** Used with VisualEngine
**THEN** Pages are rendered at 300 DPI
**AND** Output is JPEG format with 80% quality

### Scenario CFG-003: Page Range Extraction
**GIVEN** `page_range: Some(0..=4)`
**WHEN** Extraction is performed
**THEN** First 5 pages (0-4) are extracted
**AND** Page numbers in result remain 1-indexed

### Scenario CFG-004: Parallel Processing Enable
**GIVEN** `parallel: true`
**WHEN** Engine supports parallel processing
**THEN** Rayon-based parallel extraction is used
**AND** Result content matches sequential extraction

---

## Edge Case Scenarios

### Scenario CFG-EC-001: Invalid JPEG Quality
**GIVEN** `ImageFormat::Jpeg(150)` (quality > 100)
**WHEN** Used in configuration
**THEN** Engine **SHALL** clamp to valid range (0-100)
**AND** No error is returned

### Scenario CFG-EC-002: Zero DPI
**GIVEN** `Visual { dpi: 0, .. }`
**WHEN** Rendering is performed
**THEN** Engine **SHALL** use minimum valid DPI (72)
**AND** Rendering completes successfully

### Scenario CFG-EC-003: Reverse Page Range
**GIVEN** `page_range: Some(5..=2)`
**WHEN** Extraction is attempted
**THEN** Range is treated as empty
**AND** No pages are extracted

### Scenario CFG-EC-004: Empty Password
**GIVEN** `password: Some("".to_string())`
**WHEN** Extracting encrypted PDF
**THEN** Empty string is used as password attempt

---

## Technical Constraints

### Configuration Immutability
- `ExtractionConfig` fields are public
- Configuration is immutable once created
- Cloneable for reuse across multiple extractions

### Serialization
- All result types implement `Serialize`/`Deserialize` when `serde` feature is enabled
- Configuration does not require serialization by default

### Validation
- Configuration validation happens at extraction time, not construction
- Invalid values are clamped or ignored rather than causing panics

---

## Implementation Location
`crates/superwrapper-pdf/src/types.rs:94`
