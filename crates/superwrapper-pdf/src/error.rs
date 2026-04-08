//! Error types and result types for PDF extraction
//!
//! This module defines the [`SuperWrapperError`] enum which provides comprehensive
//! error reporting for all extraction operations, and the [`Result`] type alias
//! for convenient error handling.
//!
//! # Error Handling Example
//!
//! ```rust,no_run
//! use superwrapper_pdf::{FastEngine, PdfEngine, SuperWrapperError, ExtractionConfig};
//! use std::path::Path;
//!
//! # fn main() -> Result<(), Box<dyn std::error::Error>> {
//! let engine = FastEngine;
//! let config = ExtractionConfig::default();
//!
//! match engine.extract(Path::new("document.pdf"), &config) {
//!     Ok(result) => {
//!         println!("Extracted {} pages", result.page_count);
//!     }
//!     Err(SuperWrapperError::Io(e)) => {
//!         eprintln!("File access error: {}", e);
//!     }
//!     Err(SuperWrapperError::Encrypted) => {
//!         eprintln!("PDF is password-protected");
//!     }
//!     Err(SuperWrapperError::PageOutOfRange { requested, total }) => {
//!         eprintln!("Requested page {} but PDF has {} pages", requested, total);
//!     }
//!     Err(e) => {
//!         eprintln!("Extraction failed: {:?}", e);
//!     }
//! }
//! # Ok(())
//! # }
//! ```

use thiserror::Error;

/// Comprehensive error type for PDF extraction operations
///
/// Each variant represents a distinct category of failure that can occur
/// during PDF extraction. The error types are feature-gated - some variants
/// only exist when specific extraction engines are enabled.
#[derive(Error, Debug)]
pub enum SuperWrapperError {
    /// File system access errors (permission denied, file not found, etc.)
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// PDF parsing errors (corrupted file, invalid format, etc.)
    #[error("PDF parsing error: {0}")]
    PdfParse(String),

    /// Document is encrypted and requires a password
    /// Returned when no password is provided or the password is incorrect
    #[error("Encrypted PDF (no password provided or invalid)")]
    Encrypted,

    /// Requested page number exceeds document length
    /// Fields indicate which page was requested and total pages available
    #[error("Page {requested} out of range (total: {total})")]
    PageOutOfRange { requested: u32, total: u32 },

    /// Feature-gated extraction mode is not enabled
    /// Enable the appropriate feature in Cargo.toml: `structured`, `visual`, etc.
    #[error(
        "Extraction mode '{mode}' is not enabled. Build with feature '{feature}' to enable it."
    )]
    FeatureNotEnabled { mode: String, feature: String },

    /// Errors from pdf_oxide library (FastEngine failures)
    #[error("pdf_oxide error: {0}")]
    Oxide(#[from] pdf_oxide::Error),

    /// Errors from unpdf library (StructuredEngine failures)
    /// Only available when `structured` feature is enabled
    #[cfg(feature = "structured")]
    #[error("unpdf error: {0}")]
    Unpdf(#[from] unpdf::Error),

    /// Errors from pdfium-render library (VisualEngine failures)
    /// Only available when `visual` feature is enabled
    #[cfg(feature = "visual")]
    #[error("pdfium-render error: {0}")]
    Pdfium(String),
}

/// Type alias for results using SuperWrapperError
///
/// Provides a convenient shorthand for functions that return extraction results.
/// Instead of writing `Result<T, SuperWrapperError>`, you can write `Result<T>`.
pub type Result<T> = std::result::Result<T, SuperWrapperError>;
