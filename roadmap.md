# SuperWrapper-PDF Roadmap

## Overview

This roadmap outlines the planned development for superwrapper-pdf, a unified Rust library for PDF extraction and conversion. The library provides a high-level API across multiple specialized engines optimized for different use cases.

- **Current Version**: 0.1.0
- **License**: MIT OR Apache-2.0
- **Repository**: https://github.com/sopaco/superwrapper-pdf

---

## Version History

| Version | Date | Status | Notes |
|---------|------|--------|-------|
| 0.1.0 | 2026-04-08 | ✅ Released | Initial release with 3 engines, docs, examples |

---

## Roadmap

### v0.2.0 - Stabilization & Bindings Refresh

**Target**: Q2 2026

**Goals**:
- Fix and update existing language bindings
- Improve error messages and debugging
- Add more comprehensive test fixtures

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Fix Python Bindings | Update PyO3 bindings in `rust/python-bindings/` | 📋 |
| High | Fix Node.js Bindings | Update Neon bindings in `rust/nodejs-bindings/` | 📋 |
| Medium | Enhanced Error Messages | Improve error reporting with context | 📋 |
| Medium | Test Fixtures | Add more diverse PDF test samples | 📋 |
| Low | Documentation PDF | Generate API docs to docs/ | 📋 |

**Breaking Changes**: None expected

---

### v0.2.1 - Performance Improvements

**Target**: Q2 2026

**Goals**:
- Optimize memory usage for large PDFs
- Improve extraction speed
- Add progress reporting

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Memory Optimization | Reduce memory footprint for large PDFs | 📋 |
| High | Streaming Extraction | Chunked processing for large files | 📋 |
| Medium | Progress Callbacks | Real-time progress for long operations | 📋 |
| Medium | Benchmark Suite | Comprehensive performance benchmarks | 📋 |

**Breaking Changes**: None expected

---

### v0.3.0 - Async & Caching

**Target**: Q3 2026

**Goals**:
- Complete async/await support
- Add result caching
- Improve parallel processing

**Features**:

| Priority | Feature | Description | Status |
|----------|---------|-------------|--------|
| High | Full Async Runtime | Native async API with Tokio | 📋 |
| High | Result Caching | Cache extraction results | 📋 |
| High | Improved Parallelism | Better rayon integration | 📋 |
| Medium | WebAssembly Target | Compile to WASM for browser | 📋 |
| Medium | gRPC Service | Optional gRPC interface | 📋 |

**Breaking Changes**:
- `extract_async` method signature may change

---

### v1.0.0 - Feature Complete

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

- **Repository**: https://github.com/sopaco/superwrapper-pdf
- **Issues**: https://github.com/sopaco/superwrapper-pdf/issues
- **Discussions**: https://github.com/sopaco/superwrapper-pdf/discussions

---

*Last updated: 2026-04-08*
*Based on implementation research: `thoughts/research/2026-04-08_implementation_research.md`*