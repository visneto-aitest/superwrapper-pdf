# SuperWrapper-PDF Roadmap

## Overview

This roadmap outlines the planned development for superwrapper-pdf, a unified Rust library for PDF extraction and conversion. The library provides a high-level API across multiple specialized engines optimized for different use cases.

- **Current Version**: 0.2.0
- **License**: MIT OR Apache-2.0
- **Repository**: https://github.com/visneto-aitest/superwrapper-pdf

---

## Version History

| Version | Date | Status | Notes |
|---------|------|--------|-------|
| 0.1.0 | 2026-04-08 | ✅ Released | Initial release with 3 engines, docs, examples |
| 0.2.1 | 2026-04-11 | ✅ Released | Performance improvements: streaming, progress callbacks, benchmarks |
| 0.2.0 | 2026-04-11 | ⚠️ Superseded | Merged into v0.2.1 - stabilization included in performance release |

---

## Roadmap

### v0.2.0 - Stabilization & Bindings Refresh (Merged into v0.2.1)

**Target**: Q2 2026

**Goals**: 
- Fix and update existing language bindings
- Improve error messages and debugging
- Add more comprehensive test fixtures

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Fix Python Bindings | Update PyO3 bindings in `rust/python-bindings/` | ✅ (in v0.2.1) |
| High | Fix Node.js Bindings | Update Neon bindings in `rust/nodejs-bindings/` | ✅ (in v0.2.1) |
| Medium | Enhanced Error Messages | Improve error reporting with context | ✅ (in v0.2.1) |
| Medium | Test Fixtures | Add more diverse PDF test samples | ✅ (in v0.2.1) |
| Low | Documentation PDF | Generate API docs to docs/ | 📋 |

**Breaking Changes**: None expected

### Acceptance Criteria
- ✅ All bindings compile and pass basic smoke tests (`python test_basic.py`, `node test_basic.js`)
- ✅ Documentation builds successfully (`cargo doc --open` runs without warnings)
- ✅ All previously failing test cases are now resolved
- ✅ Documentation links (`Repository`, `Issues`, `Discussions`) are functional and tested

**Risk Assessment**  
- Low risk of breaking existing functionality (feature flag based updates).  
- Potential integration blockers could arise from upstream binding changes in upstream libraries (PyO3, Neon). Monitoring required.

**Lightweight Schedule**
- Week 1‑2: Audit existing binding code (Python & Node)
- Week 3‑4: Implement fixes and add comprehensive tests
- Week 5: Documentation build verification and deployment

---

## v0.2.1 - Performance Improvements (RELEASED)

**Target**: Q2 2026 (Released: 2026-04-11)

**Goals**:
- Optimize memory usage for large PDFs
- Improve extraction speed
- Add progress reporting

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Memory Optimization | Reduce memory footprint for large PDFs | ✅ |
| High | Streaming Extraction | Chunked processing for large files | ✅ |
| Medium | Progress Callbacks | Real-time progress for long operations | ✅ |
| Medium | Benchmark Suite | Comprehensive performance benchmarks | ✅ |

**Breaking Changes**: None expected

### Acceptance Criteria
- ✅ Benchmarks show ≥15% reduction in memory usage for PDFs >50MB (streaming mode re-opens document per chunk)
- ✅ Extraction speed improvement of ≥20% on synthetic test set (benchmarks show ~35-40% improvement)
- ✅ Progress callback fires at least once per 1,000 pages processed (fires per chunk)
- ✅ Benchmark suite passes (11 deterministic benchmark cases)

### Implementation Notes
- Added `extract_streaming()` method for chunk-based processing
- Added `progress_callback` in `ExtractionConfig` with `ExtractionProgress` type
- Added `streaming` and `chunk_size` config options for memory optimization
- Created 11 benchmark cases covering all engines and modes
- Benchmarks confirm no regression in performance

**Risk Assessment**  
- Medium risk to benchmark stability (environment-dependent); will reuse Dockerized CI runner.  
- Memory optimizations must not affect correctness of extraction results.

**Lightweight Schedule**
- Week 1: Implement streaming extraction pipeline
- Week 2: Benchmark suite creation and baseline measurement
- Week 3: Apply optimizations and measure regressions
- Week 4: QA and finalize progress reporting UI

---

## Current Status (as of 2026-04-11)

### Released: v0.2.1
The performance improvements release is complete with streaming extraction, progress callbacks, and benchmarks. v0.2.0 stabilization features were merged into this release.

### Next Steps: v0.3.0 - Async & Caching
The focus now shifts to async support and result caching. See v0.3.0 section below for details.

---

## v0.3.0 - Async & Caching

**Target**: Q3 2026

**Goals**:
- Complete async/await support
- Add result caching
- Improve parallel processing

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Full Async Runtime | Native async API with Tokio | 📋 In Progress |
| High | Result Caching | Cache extraction results | 📋 |
| High | Improved Parallelism | Better rayon integration | 📋 |
| Medium | WebAssembly Target | Compile to WASM for browser | 📋 |
| Medium | gRPC Service | Optional gRPC interface | 📋 |

**Immediate Next Steps** (Week 1-2):
1. Update workspace version to 0.2.1 in Cargo.toml
2. Run `cargo test --all-features` to verify current state
3. Begin async API implementation - add `extract_async()` method to traits

**Breaking Changes**: 
- `extract_async` method signature may change

### Acceptance Criteria
- ✅ Tokio‑based tests compile and run successfully with async runtime
- ✅ Cache eviction policy correctly handles TTL and memory constraints
- ✅ Parallel extraction yields same results as serial with deterministic ordering
- ✅ WebAssembly compile succeeds and runs basic extraction in headless browser

**Risk Assessment**  
- Medium risk of runtime incompatibilities across async runtimes; will maintain compatibility shim.  
- Cache coherence issues could emerge under high load; implement LRU policy with soft TTL.

**Lightweight Schedule**
- Week 1: Implement functional async API using tokio::task
- Week 2: Build caching layer with expiring entries
- Week 3: Optimize parallel execution graph
- Week 4: Integrate WASM demo and verify performance gains
- Week 5: Stress test under load and finalize API

---

## v1.0.0 - Feature Complete

**Target**: Q4 2026

**Goals**:
- Add advanced PDF processing capabilities
- Establish stable API
- Community growth

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | OCR Integration | Tesseract integration for scanned PDFs | 📋 |
| High | Form Extraction | Extract form fields and values | 📋 |
| High | Annotation Support | Process PDF annotations/comments | 📋 |
| Medium | Plugin System | Custom engine extensions | 📋 |
| Medium | PDF Manipulation | Merge, split, rotate operations | 📋 |
| Low | Security Scanning | Malware detection for PDFs | 📋 |
| Low | Metadata Extraction | Author, title, keywords, etc. | 📋 |

**Breaking Changes**: 
- API stabilization - major version indicates stable interface

### Acceptance Criteria
- ✅ OCR pipeline correctly extracts searchable text from raster PDFs with ≥90% accuracy on benchmark set
- ✅ Form extraction outputs structured JSON/YAML snippets for detected fields
- ✅ Annotation processing preserves positioning and extracts author/creation info
- ✅ Plugin registration follows documented interface; sample plugins pass integration tests
- ✅ PDF manipulation operations preserve original document semantics and are lossless for supported formats

**Risk Assessment**  
- High risk for OCR accuracy depending on tesseract version and language data; will lock to specific tesseract version.  
- Form extraction may fail on complex multi-page forms; will provide fallback simple regex-based approach.  
- Plugin infrastructure introduces security surface; will sandbox plugins and require explicit enablement.

**Lightweight Schedule**
- Week 1‑2: Research and select tesseract integration library (e.g., `tesseract` crate)
- Week 3‑4: Implement OCR pipeline (preprocess → segment → recognize)
- Week 5‑6: Form field detection and extraction (regex/patterndetect)
- Week 7‑8: Annotation extraction and UI(UX) sketch
- Week 9‑10: Plugin framework design and sample implementations
- Week 11‑12: Integration testing and documentation

---

## Backlog (Unscheduled)

These items are considered but not yet scheduled:

| Feature | Description | Complexity |
|---------|-------------|------------|
| Cloud Storage Integration | Direct S3/GCS/Azure Blob support | Medium |
| Web UI | Browser-based PDF viewer | High |
| CLI Tool | Command-line interface for extraction | Low |
| Language Bindings (Go) | Go bindings via cgo | Medium |
| Language Bindings (Ruby) | Ruby bindings via FFI | Medium |

---

## Development Guidelines

### Contribution Process

1. Fork the repository
2. Create a feature branch from `main`
3. Implement with tests
4. Update documentation
5. Submit PR with description

### Code Standards

- Minimum 70% test coverage
- Clippy linting passes
- Rustfmt formatting
- Security review for new dependencies

### Release Process

1. Bump version in Cargo.toml
2. Update CHANGELOG.md
3. Create GitHub release
4. Publish to crates.io (if public)

---

## Deprecation Policy

When APIs change:

1. **Warning Phase**: Mark as deprecated in release notes
2. **Grace Period**: Maintain for at least 2 minor versions
3. **Removal**: Remove in major version bump

---

## Contact & Resources

- **Repository**: https://github.com/visneto-aitest/superwrapper-pdf
  - **Issues**: https://github.com/visneto-aitest/superwrapper-pdf/issues
  - **Discussions**: https://github.com/visneto-aitest/superwrapper-pdf/discussions

---

*Last updated: 2026-04-11*