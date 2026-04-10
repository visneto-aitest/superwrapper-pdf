# OpenSpec: Unified Engine Interface

## Overview
Trait-based contract that all PDF extraction engines must implement to ensure consistent behavior across implementations.

## Capability: Engine Interface Contract

### Functional Requirements

#### RQ-IF-001: Core Trait Definition
The system **SHALL** define a `PdfEngine` trait with the following required methods:
- `name() -> &'static str`
- `extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult>`

#### RQ-IF-002: Name Method
All engines **MUST** return a unique, static string identifier from the `name()` method.

#### RQ-IF-003: Extract Method Contract
The `extract()` method **SHALL**:
- Accept a file system path to a PDF document
- Accept an `ExtractionConfig` instance
- Return a consistent `ExtractionResult` structure on success
- Return a typed `SuperWrapperError` on failure

#### RQ-IF-004: Async Extension
When the `async` feature is enabled, the trait **SHALL** provide an `extract_async()` method with default fallback to synchronous implementation.

#### RQ-IF-005: Send + Sync Bound
The `PdfEngine` trait **MUST** be bounded by `Send + Sync` for thread safety.

---

## Success Scenarios

### Scenario IF-001: Engine Interchangeability
**GIVEN** Any struct implementing the `PdfEngine` trait
**WHEN** The engine is used as `Box<dyn PdfEngine>`
**THEN** All trait methods are available
**AND** Behavior is consistent with concrete implementation

### Scenario IF-002: Name Uniqueness
**GIVEN** Any engine implementation
**WHEN** `name()` is called
**THEN** A non-empty static string is returned
**AND** The name is unique among all engine implementations

### Scenario IF-003: Consistent Result Format
**GIVEN** Any engine implementation
**WHEN** Extraction succeeds
**THEN** Returned `ExtractionResult` has all required fields populated
**AND** Page numbers are 1-indexed
**AND** Character counts are accurate

### Scenario IF-004: Error Context Propagation
**GIVEN** Any engine implementation
**WHEN** Extraction fails
**THEN** Error contains relevant context (file path, details)
**AND** Error type matches failure category

---

## Edge Case Scenarios

### Scenario IF-EC-001: Default Async Fallback
**GIVEN** Engine without custom async implementation
**WHEN** `extract_async()` is called
**THEN** Synchronous `extract()` method is invoked
**AND** Result is identical to synchronous call

### Scenario IF-EC-002: Empty Document
**GIVEN** A PDF with 0 pages
**WHEN** Extraction is performed
**THEN** Result indicates 0 pages
**AND** No error is returned
**AND** Text fields are empty strings

### Scenario IF-EC-003: Zero-Length File
**GIVEN** An empty file with .pdf extension
**WHEN** Extraction is attempted
**THEN** `SuperWrapperError::PdfParse` is returned

---

## Technical Constraints

### Trait Bounds
- `PdfEngine: Send + Sync`
- All implementors must be `'static`

### Method Signatures
- No method may panic under normal operation
- All errors must be returned as `Result` variants
- Returned references must have appropriate lifetimes

### Implementation Requirements
- Engines must not maintain mutable state between calls
- All configuration must be passed through `ExtractionConfig`
- Engine instances must be cloneable if stateful

---

## Implementation Location
`crates/superwrapper-pdf/src/engine/mod.rs:48`
