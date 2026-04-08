# SuperWrapper-PDF

A high-level Rust abstraction providing a unified interface for PDF extraction and conversion by orchestrating multiple specialized engines.

## Overview

SuperWrapper-PDF orchestrates three PDF processing engines, each optimized for different use cases:

| Engine | Purpose | Best For |
|--------|---------|----------|
| **FastEngine** | Quick text extraction | High-speed text extraction, large batch processing |
| **StructuredEngine** | Structured content extraction | Markdown conversion, content analysis |
| **VisualEngine** | Visual rendering | PDF-to-image conversion, visual processing |

## Features

- **Unified API** - Single interface for multiple PDF processing approaches
- **Feature-gated dependencies** - Enable only the engines you need
- **Parallel processing** - Built-in support for concurrent page extraction
- **Password-protected PDFs** - Support for encrypted PDF files
- **Page range selection** - Extract specific page ranges
- **High test coverage** - 82%+ code coverage with comprehensive tests

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
superwrapper-pdf = "0.1"
```

### Feature Flags

Enable specific engines based on your needs:

```toml
# Default: includes StructuredEngine
superwrapper-pdf = { version = "0.1", default-features = false, features = ["structured"] }

# Fast only (no optional dependencies)
superwrapper-pdf = { version = "0.1", default-features = false, features = [] }

# All engines
superwrapper-pdf = { version = "0.1", features = ["all"] }

# Individual engines
superwrapper-pdf = { version = "0.1", features = ["structured", "visual"] }
```

| Feature | Description |
|---------|-------------|
| `structured` | Enable StructuredEngine (uses `unpdf` crate) |
| `visual` | Enable VisualEngine (uses `pdfium-render` crate) |
| `async` | Enable async support for all engines |
| `all` | Enable all optional engines |

## Usage

### Examples

The crate includes comprehensive examples demonstrating various usage patterns:

#### FastEngine Example
Quick text extraction optimized for speed:

```rust
use superwrapper_pdf::{FastEngine, PdfEngine, ExtractionConfig};
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;
    let config = ExtractionConfig::default();
    
    let result = engine.extract(Path::new("document.pdf"), &config)?;
    
    println!("Extracted {} characters from {} pages", 
             result.text.len(), result.page_count);
    
    Ok(())
}
```

#### StructuredEngine Example
Markdown conversion with parallel processing:

```rust
use superwrapper_pdf::{StructuredEngine, PdfEngine, ExtractionConfig, ExtractionMode};
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = StructuredEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        parallel: true,  // Enable parallel extraction
        ..Default::default()
    };
    
    let result = engine.extract(Path::new("document.pdf"), &config)?;
    
    println!("Generated {} characters of markdown", result.markdown.len());
    
    Ok(())
}
```

#### VisualEngine Example
PDF-to-image rendering with configurable DPI and format:

```rust
use superwrapper_pdf::{VisualEngine, PdfEngine, ExtractionConfig, ExtractionMode, ImageFormat};
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual { 
            dpi: 300,
            format: ImageFormat::Jpeg(85),  // or ImageFormat::Png
        },
        ..Default::default()
    };
    
    let result = engine.extract(Path::new("document.pdf"), &config)?;
    
    println!("Rendered {} pages as images", result.pages.len());
    
    Ok(())
}
```

#### Async Example
Concurrent processing using Tokio:

```rust
use superwrapper_pdf::{PdfEngine, ExtractionConfig, ExtractionMode};
use std::path::Path;
use tokio::task;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Process multiple PDFs concurrently
    let fast_task = task::spawn(async {
        let engine = superwrapper_pdf::FastEngine;
        let config = ExtractionConfig::default();
        engine.extract(Path::new("document1.pdf"), &config)
    });
    
    let structured_task = task::spawn(async {
        let engine = superwrapper_pdf::StructuredEngine;
        let config = ExtractionConfig {
            mode: ExtractionMode::Structured,
            parallel: true,
            ..Default::default()
        };
        engine.extract(Path::new("document2.pdf"), &config)
    });
    
    // Wait for both operations to complete
    let (fast_result, structured_result) = tokio::join!(fast_task, structured_task);
    
    println!("Fast extraction: {:?}", fast_result);
    println!("Structured extraction: {:?}", structured_result);
    
    Ok(())
}
```

### Async Support

SuperWrapper-PDF includes optional async support that allows you to process PDFs concurrently. When the `async` feature is enabled, all engines implement the `extract_async` method which can be used with async runtimes like Tokio:

```toml
superwrapper-pdf = { version = "0.1", features = ["all", "async"] }
tokio = { version = "1.0", features = ["full"] }
```

The async implementation leverages Tokio's thread pool to run CPU-intensive PDF processing operations without blocking the async executor.
        format: ImageFormat::Png,  // or ImageFormat::Jpeg(80)
    },
    ..Default::default()
};

let result = engine.extract("document.pdf", &config).unwrap();

// Access per-page text content
for page in &result.pages {
    println!("Page {}: {} chars", page.page_number, page.char_count);
}
```

### Advanced Configuration

```rust
use superwrapper_pdf::{ExtractionConfig, ExtractionMode, ImageFormat};

let config = ExtractionConfig {
    // Password for encrypted PDFs
    password: Some("secret"),
    
    // Extract specific page range (0-indexed)
    page_range: Some(0..=5),
    
    // Engine-specific options
    mode: ExtractionMode::Visual {
        dpi: 300,
        format: ImageFormat::Jpeg(85),
    },
};

// Use with any engine
let engine = FastEngine;
let result = engine.extract_with_config("document.pdf", config);
```

## API Reference

### Core Types

```rust
// Main extraction configuration
pub struct ExtractionConfig {
    pub mode: ExtractionMode,      // Extraction mode selection
    pub password: Option<String>,   // PDF password (if encrypted)
    pub page_range: Option<Range<usize>>,  // Page range to extract
}

// Extraction mode variants
pub enum ExtractionMode {
    Fast,                           // FastEngine mode
    Structured { parallel: bool },  // StructuredEngine with optional parallelism
    Visual { dpi: u32, format: ImageFormat },  // VisualEngine with render options
}

// Output format for VisualEngine
pub enum ImageFormat {
    Png,
    Jpeg(u8),  // Quality 0-100
}

// Extraction results
pub struct ExtractionResult {
    pub markdown: String,       // Markdown-formatted content (StructuredEngine)
    pub text: String,           // Plain text content
    pub page_count: usize,      // Total pages in PDF
    pub pages: Vec<PageInfo>,   // Per-page details
    pub source: Option<PathBuf>,  // Source file path
}

// Per-page information
pub struct PageInfo {
    pub page_number: usize,     // 1-indexed page number
    pub char_count: usize,      // Character count for this page
    pub text: String,          // Page-specific text content
}
```

### Engine Trait

All engines implement the `PdfEngine` trait:

```rust
pub trait PdfEngine {
    fn name(&self) -> &'static str;
    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult>;
    
    #[cfg(feature = "async")]
    fn extract_async(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult> {
        // Default implementation falls back to sync extraction
        self.extract(path, config)
    }
}
```

## Error Handling

```rust
use superwrapper_pdf::{SuperWrapperError, Result};

match engine.extract("document.pdf", &config) {
    Ok(result) => { /* handle success */ }
    Err(SuperWrapperError::FileNotFound(path)) => { /* handle missing file */ }
    Err(SuperWrapperError::PasswordRequired) => { /* handle encrypted PDF */ }
    Err(SuperWrapperError::PageOutOfRange { requested, total }) => {
        eprintln!("Requested page {} but PDF has {} pages", requested, total);
    }
    Err(e) => { /* handle other errors */ }
}
```

## Testing

Run tests with:

```bash
# Run all tests
cargo test

# Run with coverage
cargo tarpaulin --ignore-panics

# Run specific engine tests
cargo test fast      # FastEngine tests
cargo test structured  # StructuredEngine tests  
cargo test visual    # VisualEngine tests
```

### Test Fixtures

Test PDF fixtures are located in `tests/fixtures/`:
- `sample.pdf` - Multi-page sample with text and images
- `minimal.pdf` - Minimal single-page PDF
- `simple.pdf` - Simple text-only PDF

## Architecture

```
superwrapper-pdf
├── Cargo.toml              # Workspace configuration
├── README.md               # This file
└── crates/
    └── superwrapper-pdf/
        ├── Cargo.toml      # Library configuration
        └── src/
            ├── lib.rs          # Public API exports
            ├── engine/
            │   ├── mod.rs      # PdfEngine trait definition
            │   ├── fast.rs     # FastEngine implementation
            │   ├── structured.rs  # StructuredEngine implementation
            │   └── visual.rs   # VisualEngine implementation
            ├── types.rs        # Core data structures
            └── error.rs        # Error types
```

## Engine Details

### FastEngine
- Uses `pdf_oxide` crate
- Optimized for raw speed
- Plain text extraction only
- No optional features required

### StructuredEngine
- Uses `unpdf` crate
- Extracts structured markdown
- Supports parallel page processing
- Requires `structured` feature

### VisualEngine
- Uses `pdfium-render` crate
- Renders pages to images (PNG/JPEG)
- Extracts per-page text content
- Requires `visual` feature and system pdfium library

## License

MIT OR Apache-2.0