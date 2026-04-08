# superwrapper-pdf Python Bindings

Python bindings for the `superwrapper-pdf` Rust library, providing fast PDF text and markdown extraction.

## Installation

### From Source

```bash
# Install maturin (if not already installed)
pip install maturin

# Build and install the package
maturin develop
```

### Development

```bash
# For development with hot reload
maturin develop

# Build release version
maturin build --release

# Build wheel for distribution
maturin build --release
```

## Usage

```python
from superwrapper_pdf import extract_pdf, ExtractionConfig

# Simple extraction
result = extract_pdf("document.pdf")
print(f"Pages: {result.page_count}")
print(f"Text: {result.text[:200]}...")

# With configuration
config = ExtractionConfig(
    mode="structured",  # or "fast"
    page_range=(0, 2),  # pages 1-3 (0-indexed)
    parallel=True
)
result = extract_pdf("document.pdf", config)
print(f"Markdown: {result.markdown[:200]}...")

# Access page details
for page in result.pages:
    print(f"Page {page.page_number}: {page.char_count} chars")
```

## API Reference

### Functions

- `extract_pdf(path: str, config: ExtractionConfig = None) -> ExtractionResult`

### Classes

#### `ExtractionResult`
- `markdown: str` - Extracted markdown content (if available)
- `text: str` - Plain text content
- `page_count: int` - Total number of pages
- `pages: list[PageInfo]` - Per-page metadata
- `source: str | None` - Source file path

#### `PageInfo`
- `page_number: int` - 1-indexed page number
- `text: str` - Page text content
- `char_count: int` - Character count

#### `ExtractionConfig`
- `mode: str` - Extraction mode ("fast", "structured", "visual")
- `page_range: tuple[int, int] | None` - Page range (0-indexed inclusive)
- `password: str | None` - Password for encrypted PDFs
- `parallel: bool` - Enable parallel processing

## Requirements

- Python 3.8+
- Rust 1.70+

## Features

- **Fast Mode**: Quick text extraction using pdf_oxide
- **Structured Mode**: Markdown/table extraction using unpdf
- **Page Selection**: Extract specific page ranges
- **Parallel Processing**: Multi-threaded extraction for large PDFs
- **Error Handling**: Comprehensive error reporting

## License

MIT License - see LICENSE file in the root directory.