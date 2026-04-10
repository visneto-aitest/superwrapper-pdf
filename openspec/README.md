# OpenSpec Source of Truth: SuperWrapper-PDF

## System Overview
SuperWrapper-PDF is a Rust-based PDF processing abstraction layer that unifies three specialized PDF extraction engines behind a single consistent API.

## Capability Inventory

| Capability | Status | Specification |
|------------|--------|---------------|
| PDF Extraction Core | ✅ Complete | [specs/pdf-extraction/spec.md](specs/pdf-extraction/spec.md) |
| Unified Engine Interface | ✅ Complete | [specs/unified-engine-interface/spec.md](specs/unified-engine-interface/spec.md) |
| Fast Text Extraction | ✅ Complete | [specs/fast-text-extraction/spec.md](specs/fast-text-extraction/spec.md) |
| Extraction Configuration | ✅ Complete | [specs/configuration/spec.md](specs/configuration/spec.md) |
| Error Handling | ✅ Complete | [specs/error-handling/spec.md](specs/error-handling/spec.md) |
| Structured Markdown Extraction | ✅ Complete | [specs/structured-extraction/spec.md](specs/structured-extraction/spec.md) |
| Visual Image Rendering | ✅ Complete | [specs/visual-rendering/spec.md](specs/visual-rendering/spec.md) |

## Engine Matrix

| Engine | Backend | Dependencies | Speed | Output Format |
|--------|---------|--------------|-------|---------------|
| FastEngine | pdf_oxide | None | ⚡⚡⚡ | Plain Text |
| StructuredEngine | unpdf | `structured` feature | ⚡⚡ | Markdown + Text |
| VisualEngine | pdfium-render | `visual` feature + system pdfium | ⚡ | Images + Text |

## Technical Constraints Summary

### Runtime
- **Rust MSRV**: 1.75+
- **Async**: Tokio 1.0+ (optional)
- **Parallel**: Rayon 1.0+ (optional)

### Features
- All engines are feature-gated
- Default features: `structured`
- `all` feature enables all engines
- `async` feature enables async/await support

### Performance Characteristics
- FastEngine: <10ms/page
- StructuredEngine: <50ms/page
- VisualEngine: <300ms/page @ 150 DPI

## Compliance
All capabilities adhere to the requirements defined in their respective specifications. Each requirement includes success scenarios and edge case handling with GIVEN-WHEN-THEN testable specifications.

---

*Generated: 2026-04-10*
*Source: Reverse-engineered from crates/superwrapper-pdf/src/*
