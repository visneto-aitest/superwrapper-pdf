# Brainstorming: Missing Features & Gaps

This document outlines potential improvements, missing features, and gaps in the current superwrapper-pdf solution.

## 1. Extraction Engine Gaps

### 1.1 Unified Engine Selection
- **Gap**: No unified entry point that auto-selects engine based on config
- **Idea**: `AutoEngine` that picks Fast/Structured/Visual based on output needs

### 1.2 Hybrid Extraction
- **Gap**: Cannot combine outputs from multiple engines in single pass
- **Idea**: Extract text + markdown + images in one operation

### 1.3 OCR Engine
- **Gap**: No OCR support for scanned PDFs
- **Idea**: Add Tesseract integration for image-based PDFs

## 2. Output Format Gaps

### 2.1 JSON Output
- **Gap**: Only markdown for structured output
- **Idea**: Add `ExtractionMode::Json` with schema (title, headings, paragraphs, tables, images)

### 2.2 HTML Output
- **Gap**: No HTML rendering
- **Idea**: Add `ExtractionMode::Html` for web-viewable output

### 2.3 Plain Text Cleanup
- **Gap**: Raw text contains PDF artifacts (page numbers, headers)
- **Idea**: Add text cleanup/formatting options (remove headers, fix hyphenation)

## 3. Configuration Gaps

### 3.1 Table Extraction
- **Gap**: No dedicated table handling
- **Idea**: `extract_tables: bool` option with CSV/JSON table output

### 3.2 Image Extraction
- **Gap**: Cannot extract embedded images separately
- **Idea**: Option to extract images as separate files with references

### 3.3 Metadata Extraction
- **Gap**: Basic metadata only (page count, source)
- **Idea**: Extract PDF metadata (author, creator, creation date, keywords)

### 3.4 Language Detection
- **Gap**: No language detection
- **Idea**: Add language detection for multilingual PDFs

## 4. Performance Gaps

### 4.1 Caching
- **Gap**: Basic file-based caching exists but limited
- **Idea**: Redis/memcached caching layer, cache invalidation strategies

### 4.2 Incremental Extraction
- **Gap**: No difference detection for updated PDFs
- **Idea**: Incremental extraction that only extracts new/changed pages

### 4.3 Memory Optimization
- **Gap**: Large PDFs still use significant memory
- **Idea**: Zero-copy extraction, memory-mapped file processing

### 4.4 Batch Optimization
- **Gap**: Each PDF processed independently
- **Idea**: Batch processing with worker pools and job queues

## 5. Error Handling Gaps

### 5.1 Recovery Strategies
- **Gap**: Hard failures on corrupted pages
- **Idea**: Skip corrupted pages, continue extraction, report partial success

### 5.2 Detailed Error Context
- **Gap**: Basic error messages
- **Idea**: Error codes, recovery suggestions, structured error details

### 5.3 Retry Logic
- **Gap**: No built-in retry
- **Idea**: Exponential backoff, retry on transient failures

## 6. API/Interface Gaps

### 6.1 WASM Support
- **Gap**: No WASM binding for browser use
- **Idea**: Publish `superwrapper-pdf-wasm` for JavaScript environments

### 6.2 gRPC API
- **Gap**: No RPC server
- **Idea**: Optional gRPC service for distributed extraction

### 6.3 CLI Tool
- **Gap**: Only library
- **Idea**: `superwrapper` CLI with multiple output formats

### 6.4 Docker Support
- **Gap**: No official Docker image
- **Idea**: Publish to Docker Hub with pdfium baked in

## 7. Quality Gaps

### 7.1 Layout Preservation
- **Gap**: Markdown loses complex layouts
- **Idea**: Better layout preservation modes (columns, floats)

### 7.2 Table of Contents
- **Gap**: No TOC extraction
- **Idea**: Extract TOC as structured data

### 7.3 Form Extraction
- **Gap**: No form field extraction
- **Idea**: Extract PDF form data to JSON

### 7.4 Annotation Extraction
- **Gap**: No annotation/footnote extraction
- **Idea**: Option to include annotations in output

## 8. Testing Gaps

### 8.1 Test Fixtures
- **Gap**: Limited test fixtures
- **Idea**: More diverse PDF test corpus (tables, forms, scanned, encrypted)

### 8.2 Golden Output
- **Gap**: No golden output tests
- **Idea**: Regression testing with golden outputs

### 8.3 Fuzzing
- **Gap**: No fuzzing tests
- **Idea**: AFL/libFuzzer integration

## 9. Documentation Gaps

### 9.1 API Docs
- **Gap**: Basic doc comments
- **Idea**: Full API documentation with examples

### 9.2 Migration Guide
- **Gap**: No migration from other libraries
- **Idea**: Migration guide from pdfplumber, PyPDF2, etc.

### 9.3 Benchmark Data
- **Gap**: No published benchmarks
- **Idea**: Performance comparison with alternatives

## 10. Security Gaps

### 10.1 PDF Sanitization
- **Gap**: No malicious PDF detection/sanitization
- **Idea**: Strip JavaScript, external references, embedded files

### 10.2 Resource Limits
- **Gap**: No resource limits
- **Idea**: Max pages, max memory, max processing time limits

## Prioritized Ideas

| Rank | Feature | Impact | Effort |
|------|---------|--------|--------|
| 1 | CLI Tool | High | Medium |
| 2 | JSON Output | High | Low |
| 3 | Table Extraction | High | Medium |
| 4 | Partial Error Recovery | Medium | Medium |
| 5 | Metadata Extraction | Medium | Low |
| 6 | WASM Support | High | High |
| 7 | OCR Engine | High | High |
| 8 | Docker Image | Medium | Low |

## Discussion Notes

- Focus on core extraction quality first before adding output formats
- Consider async/streaming as critical for production
- Priority should be on features with clear use cases