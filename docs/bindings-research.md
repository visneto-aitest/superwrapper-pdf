# Building Language Bindings for superwrapper-pdf

This document outlines the approach for building Python (PyO3) and Node.js (neonless) bindings for the Rust library `superwrapper-pdf`.

## Library Overview

`superwrapper-pdf` is a Rust library providing unified PDF extraction and conversion. Key components:

- **Core types** (`types.rs`): `ExtractionResult`, `PageInfo`, `ExtractionConfig`, `ExtractionMode`, `ImageFormat`
- **Error handling** (`error.rs`): `SuperWrapperError` enum using `thiserror`
- **Engine trait** (`engine/mod.rs`): `PdfEngine` trait implemented by `FastEngine`, `StructuredEngine`, `VisualEngine`

### Features
- `default` / `structured`: Uses `unpdf` for markdown/JSON extraction
- `visual`: Uses `pdfium-render` for image rendering
- `all`: Enables all features

---

## Python Bindings: PyO3

### Project Structure

```
superwrapper-pdf-python/
├── Cargo.toml          # pyo3-maturin project
├── pyproject.toml      # Python package config
├── src/
│   └── lib.rs          # Python module bindings
└── tests/
    └── test_extraction.py
```

### Cargo.toml

```toml
[package]
name = "superwrapper-pdf"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
pyo3 = { version = "0.20", features = ["extension-module"] }
superwrapper-pdf = { path = "../crates/superwrapper-pdf", default-features = false, features = ["structured"] }
```

### Key Binding Patterns

#### 1. Module Initialization

```rust
use pyo3::prelude::*;

#[pymodule]
fn superwrapper_pdf(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<PyExtractionResult>()?;
    m.add_class::<PyExtractionConfig>()?;
    m.add_class::<PyExtractionMode>()?;
    m.add_class::<PyPageInfo>()?;
    m.add_function(wrap_pyfunction!(extract_pdf, m)?)?;
    Ok(())
}
```

#### 2. Exposing Structs

```rust
#[pyclass]
pub struct PyExtractionResult {
    pub markdown: String,
    pub text: String,
    pub page_count: u32,
    pub pages: Vec<PyPageInfo>,
    pub source: Option<String>,
}

#[pymethods]
impl PyExtractionResult {
    fn __repr__(&self) -> String {
        format!("ExtractionResult(pages={})", self.page_count)
    }
}

#[pyclass]
pub struct PyPageInfo {
    pub page_number: u32,
    pub text: String,
    pub char_count: usize,
}
```

#### 3. Exposing Enums

```rust
#[pyclass]
#[derive(Clone)]
pub struct PyExtractionMode(PyExtractionModeInner);

#[derive(Clone, FromPyObject)]
enum PyExtractionModeInner {
    Fast,
    Structured,
    Visual { dpi: u32, format: String },
}

impl From<superwrapper_pdf::ExtractionMode> for PyExtractionMode {
    fn from(mode: superwrapper_pdf::ExtractionMode) -> Self {
        match mode {
            ExtractionMode::Fast => PyExtractionMode(PyExtractionModeInner::Fast),
            ExtractionMode::Structured => PyExtractionMode(PyExtractionModeInner::Structured),
            ExtractionMode::Visual { dpi, format } => {
                let format_str = match format {
                    ImageFormat::Png => "png".to_string(),
                    ImageFormat::Jpeg(q) => format!("jpeg:{}", q),
                };
                PyExtractionMode(PyExtractionModeInner::Visual { dpi, format: format_str })
            }
        }
    }
}
```

#### 4. Config and Function Binding

```rust
#[pyclass]
pub struct PyExtractionConfig {
    pub mode: PyExtractionMode,
    pub page_range: Option<(u32, u32)>,
    pub password: Option<String>,
    pub parallel: bool,
}

#[pymethods]
impl PyExtractionConfig {
    #[new]
    fn new(
        mode: PyExtractionMode,
        page_range: Option<(u32, u32)>,
        password: Option<String>,
        parallel: bool,
    ) -> Self {
        let mode_inner = match mode.0 {
            PyExtractionModeInner::Fast => ExtractionMode::Fast,
            PyExtractionModeInner::Structured => ExtractionMode::Structured,
            PyExtractionModeInner::Visual { dpi, format } => {
                let img_format = if format.starts_with("jpeg") {
                    let q = format.split(':').nth(1).unwrap_or("80").parse().unwrap_or(80);
                    ImageFormat::Jpeg(q)
                } else {
                    ImageFormat::Png
                };
                ExtractionMode::Visual { dpi, format: img_format }
            }
        };
        
        PyExtractionConfig {
            mode: PyExtractionMode(mode_inner),
            page_range,
            password,
            parallel,
        }
    }
}

#[pyfunction]
pub fn extract_pdf(path: String, config: PyExtractionConfig) -> PyResult<PyExtractionResult> {
    let path = std::path::PathBuf::from(&path);
    let mode = match config.mode.0 {
        PyExtractionModeInner::Fast => ExtractionMode::Fast,
        PyExtractionModeInner::Structured => ExtractionMode::Structured,
        PyExtractionModeInner::Visual { dpi, format } => {
            let img_format = if format.starts_with("jpeg") {
                let q = format.split(':').nth(1).unwrap_or("80").parse().unwrap_or(80);
                ImageFormat::Jpeg(q)
            } else {
                ImageFormat::Png
            };
            ExtractionMode::Visual { dpi, format: img_format }
        }
    };
    
    let rust_config = superwrapper_pdf::ExtractionConfig {
        mode,
        page_range: config.page_range.map(|(s, e)| s..=e),
        password: config.password,
        parallel: config.parallel,
    };
    
    let engine = superwrapper_pdf::FastEngine::new();
    let result = engine.extract(&path, &rust_config)
        .map_err(|e| pyo3::exceptions::PyRuntimeError::new_err(e.to_string()))?;
    
    Ok(PyExtractionResult {
        markdown: result.markdown,
        text: result.text,
        page_count: result.page_count,
        pages: result.pages.into_iter().map(PyPageInfo::from).collect(),
        source: result.source.map(|p| p.to_string_lossy().to_string()),
    })
}
```

#### 5. From Implementations

```rust
impl From<superwrapper_pdf::PageInfo> for PyPageInfo {
    fn from(info: superwrapper_pdf::PageInfo) -> Self {
        PyPageInfo {
            page_number: info.page_number,
            text: info.text,
            char_count: info.char_count,
        }
    }
}
```

### Python Usage

```python
from superwrapper_pdf import extract_pdf, ExtractionConfig, ExtractionMode

# Simple extraction
result = extract_pdf("document.pdf")
print(result.text)
print(result.markdown)

# With config
config = ExtractionConfig(
    mode=ExtractionMode.Structured,
    page_range=(0, 2),
    parallel=True
)
result = extract_pdf("document.pdf", config)
print(f"Extracted {result.page_count} pages")
```

### Build & Distribution

```toml
# pyproject.toml
[build-system]
requires = ["maturin"]
build-backend = "maturin"

[project]
name = "superwrapper-pdf"
requires-python = ">=3.8"
```

```bash
# Development
maturin develop

# Build wheel
maturin build --release

# Build for multiple platforms (cross-compilation)
pip install . --target x86_64-pc-windows-msvc
```

---

## Node.js Bindings: Neon (Neonless)

"Neonless" refers to building Node.js bindings without using the full Neon framework—instead using N-API directly for broader compatibility.

### Project Structure

```
superwrapper-pdf-napi/
├── binding.gyp         # Node.js native build config
├── package.json
├── src/
│   ├── lib.rs          # Rust N-API bindings
│   └── main.rs         # Node addon entry
└── test/
    └── test.js
```

### Cargo.toml

```toml
[package]
name = "superwrapper-pdf-napi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
napi = "2"
napi-derive = "2"
superwrapper-pdf = { path = "../crates/superwrapper-pdf", default-features = false, features = ["structured"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[target.'cfg(not(target_os = "windows"))'.dependencies]
libc = "0.2"
```

### N-API Bindings Pattern

```rust
use napi::{Env, JsObject, Result as NapiResult};
use napi_derive::{js_function, module_export};
use superwrapper_pdf::{FastEngine, ExtractionConfig, ExtractionResult, ExtractionMode};

#[js_function]
pub fn extract(env: Env, path: String, options: Option<JsObject>) -> NapiResult<JsObject> {
    let path_buf = std::path::PathBuf::from(&path);
    
    let mut config = ExtractionConfig::default();
    config.mode = ExtractionMode::Structured;
    
    if let Some(opts) = options {
        // Parse options from JS object
        if let Ok(parallel) = opts.get("parallel") {
            if let Ok(v) = parallel.coerce_to_bool() {
                config.parallel = v;
            }
        }
    }
    
    let engine = FastEngine::new();
    let result = engine.extract(&path_buf, &config)
        .map_err(|e| napi::Error::new(napi::Status::GenericFailure, e.to_string()))?;
    
    // Convert to JS object
    let obj = env.create_object()?;
    
    let text = env.create_string(&result.text)?;
    obj.set("text", text)?;
    
    let markdown = env.create_string(&result.markdown)?;
    obj.set("markdown", markdown)?;
    
    let page_count = env.create_uint32(result.page_count)?;
    obj.set("pageCount", page_count)?;
    
    // Pages array
    let pages_array = env.create_array(result.pages.len() as u32)?;
    for (i, page) in result.pages.into_iter().enumerate() {
        let page_obj = env.create_object()?;
        page_obj.set("pageNumber", env.create_uint32(page.page_number)?)?;
        page_obj.set("text", env.create_string(&page.text)?)?;
        page_obj.set("charCount", env.create_size(page.char_count)?)?;
        pages_array.set_element(i as u32, page_obj)?;
    }
    obj.set("pages", pages_array)?;
    
    if let Some(source) = result.source {
        obj.set("source", env.create_string(&source.to_string_lossy())?)?;
    }
    
    Ok(obj)
}

#[module_export]
pub fn init(mut exports: JsObject) -> NapiResult<()> {
    exports.create_named_method("extract", extract)?;
    Ok(())
}
```

### binding.gyp

```python
{
  "targets": [
    {
      "target_name": "superwrapper_pdf",
      "sources": [ "src/lib.rs" ],
      "dependencies": [ "<!(node -e \"require('napi-build-utils')\")" ],
      "cflags": [ "-fvisibility=hidden" ],
      "defines": [ "NAPI_EXPERIMENTAL" ],
      "conditions": [
        ["OS=='mac'", {
          'xcode_settings': {
            'OTHER_CFLAGS': ['-fembed-bitcode-marker']
          }
        }]
      ]
    }
  ]
}
```

### package.json

```json
{
  "name": "superwrapper-pdf",
  "version": "0.1.0",
  "main": "index.js",
  "scripts": {
    "install": "node-gyp configure && node-gyp build",
    "test": "node test/test.js"
  },
  "dependencies": {
    "node-addon-api": "^7.0.0"
  },
  "devDependencies": {
    "node-gyp": "^9.4.0"
  }
}
```

### Node.js Usage

```javascript
const superwrapper = require('./index.js');

async function main() {
  const result = await superwrapper.extract('document.pdf', {
    parallel: true,
    // pageRange: [0, 2]
  });
  
  console.log('Pages:', result.pageCount);
  console.log('Text:', result.text.substring(0, 200));
  console.log('Markdown:', result.markdown.substring(0, 200));
}

main().catch(console.error);
```

---

## Build Considerations

### Cross-Platform Compilation

| Platform | Toolchain |
|----------|-----------|
| Windows (x64) | MSVC |
| macOS (x64, arm64) | Clang |
| Linux (x64, arm64) | GCC |

### Dependencies

- **pdf_oxide**: No external deps (bundled)
- **unpdf**: Requires `poppler` system library
- **pdfium-render**: Requires `pdfium` binary

For bundled/standalone builds, consider:
- Using `pdf_oxide` only (no external deps)
- Static linking against pdfium

### Error Handling

Map Rust errors to idiomatic errors in each language:
- **Python**: `RuntimeError`, `ValueError`, `FileNotFoundError`
- **Node.js**: `Error` with appropriate code (`ERR_INVALID_ARG`, `ENOENT`)

---

## Implementation Roadmap

1. **Phase 1**: Core extraction API (`extract(path, config)`)
   - Expose `ExtractionResult`, `PageInfo`
   - Support `Fast` and `Structured` modes

2. **Phase 2**: Full config support
   - `page_range`, `password`, `parallel` options
   - Visual mode (image extraction)

3. **Phase 3**: Async variants
   - Python: async/await with `asyncio`
   - Node.js: Promises or async worker threads

4. **Phase 4**: Streaming (for large PDFs)
   - Python: generators
   - Node.js: streams