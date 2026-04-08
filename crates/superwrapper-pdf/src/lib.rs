//! SuperWrapper-PDF: A unified PDF extraction and conversion library
//!
//! This library provides a high-level, unified interface for PDF extraction by orchestrating
//! multiple specialized engines, each optimized for different use cases:
//!
//! | Engine | Purpose | Best For |
//! |--------|---------|----------|
//! | [`FastEngine`] | Quick text extraction | High-speed text extraction, large batch processing |
//! | [`StructuredEngine`] | Structured content extraction | Markdown conversion, content analysis |
//! | [`VisualEngine`] | Visual rendering | PDF-to-image conversion, visual processing |
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use superwrapper_pdf::{FastEngine, PdfEngine, ExtractionConfig};
//! use std::path::Path;
//!
//! # fn main() -> Result<(), Box<dyn std::error::Error>> {
//! let engine = FastEngine;
//! let config = ExtractionConfig::default();
//! let result = engine.extract(Path::new("document.pdf"), &config)?;
//! println!("Extracted {} characters from {} pages", result.text.len(), result.page_count);
//! # Ok(())
//! # }
//! ```
//!
//! ## Feature-Gated Engines
//!
//! Engines are enabled through Cargo features:
//!
//! ```toml
//! # Default: includes StructuredEngine
//! superwrapper-pdf = { version = "0.1", default-features = false, features = ["structured"] }
//!
//! # Fast only (no optional dependencies)
//! superwrapper-pdf = { version = "0.1", default-features = false, features = [] }
//!
//! # All engines with async support
//! superwrapper-pdf = { version = "0.1", features = ["all", "async"] }
//!
//! # Individual engines
//! superwrapper-pdf = { version = "0.1", features = ["structured", "visual"] }
//! ```
//!
//! ## Thread Safety and Performance
//!
//! All engines implement [`Send`] and [`Sync`] traits, making them safe to share across threads.
//! The library uses [`rayon`] for parallel processing where beneficial, and integrates with
//! [`tokio`] for async support when the `async` feature is enabled.
//!
//! ## Error Handling
//!
//! The library uses the [`SuperWrapperError`] type for comprehensive error reporting:
//!
//! ```rust,no_run
//! use superwrapper_pdf::{FastEngine, PdfEngine, SuperWrapperError};
//! use std::path::Path;
//!
//! # fn main() -> Result<(), Box<dyn std::error::Error>> {
//! let engine = FastEngine;
//! let result = engine.extract(Path::new("document.pdf"), &Default::default());
//!
//! match result {
//!     Ok(extraction) => println!("Success: {} pages", extraction.page_count),
//!     Err(SuperWrapperError::Io(e)) if e.kind() == std::io::ErrorKind::NotFound =>
//!         eprintln!("File not found"),
//!     Err(SuperWrapperError::Encrypted) => eprintln!("Document requires password"),
//!     Err(e) => eprintln!("Other error: {:?}", e),
//! }
//! # Ok(())
//! # }
//! ```

pub mod engine;
pub mod error;
pub mod types;

#[cfg(feature = "visual")]
pub use engine::VisualEngine;
pub use engine::{FastEngine, PdfEngine, StructuredEngine};
pub use error::{Result, SuperWrapperError};
pub use types::{ExtractionConfig, ExtractionMode, ExtractionResult, ImageFormat, PageInfo};
