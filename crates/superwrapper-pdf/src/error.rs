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
//!     Err(SuperWrapperError::Io { source, .. }) => {
//!         eprintln!("File access error: {}", source);
//!     }
//!     Err(SuperWrapperError::Encrypted { .. }) => {
//!         eprintln!("PDF is password-protected");
//!     }
//!     Err(SuperWrapperError::PageOutOfRange { requested, total, .. }) => {
//!         eprintln!("Requested page {} but PDF has {} pages", requested, total);
//!     }
//!     Err(e) => {
//!         eprintln!("Extraction failed: {:?}", e);
//!     }
//! }
//! # Ok(())
//! # }
//! ```

use std::path::Path;
use thiserror::Error;

/// Comprehensive error type for PDF extraction operations
///
/// Each variant represents a distinct category of failure that can occur
/// during PDF extraction. The error types are feature-gated - some variants
/// only exist when specific extraction engines are enabled.
///
/// # Context Enhancement
///
/// All errors include contextual information when available. Use the
/// [`SuperWrapperError::context()`] method to add file path context to errors.
/// Use [`SuperWrapperError::path()`] to retrieve the path from an error.
#[derive(Error, Debug)]
pub enum SuperWrapperError {
    /// File system access errors (permission denied, file not found, etc.)
    #[error("IO error: {source}")]
    Io {
        /// The file path that was being accessed
        #[doc(hidden)]
        path: Option<String>,
        /// The underlying IO error
        source: std::io::Error,
    },

    /// PDF parsing errors (corrupted file, invalid format, etc.)
    #[error("PDF parsing error: {details}")]
    PdfParse {
        /// The file path that was being parsed
        #[doc(hidden)]
        path: Option<String>,
        /// Details about what went wrong
        details: String,
    },

    /// Document is encrypted and requires a password
    /// Returned when no password is provided or the password is incorrect
    #[error("Encrypted PDF (password required)")]
    Encrypted {
        /// The file path of the encrypted document
        #[doc(hidden)]
        path: Option<String>,
    },

    /// Requested page number exceeds document length
    /// Fields indicate which page was requested and total pages available
    #[error("Page {requested} out of range (document has {total} pages)")]
    PageOutOfRange {
        /// The page number that was requested
        requested: u32,
        /// Total number of pages in the document
        total: u32,
        /// The file path (if available)
        #[doc(hidden)]
        path: Option<String>,
    },

    /// Feature-gated extraction mode is not enabled
    /// Enable the appropriate feature in Cargo.toml: `structured`, `visual`, etc.
    #[error(
        "Extraction mode '{mode}' is not enabled. Add feature '{feature}' to Cargo.toml to enable."
    )]
    FeatureNotEnabled {
        /// The mode that was requested
        mode: String,
        /// The feature that needs to be enabled
        feature: String,
    },

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
    #[error("pdfium-render error: {message}")]
    Pdfium {
        /// The underlying error message
        message: String,
        /// The file path (if available)
        #[doc(hidden)]
        path: Option<String>,
    },
}

impl From<std::io::Error> for SuperWrapperError {
    fn from(err: std::io::Error) -> Self {
        SuperWrapperError::Io {
            path: None,
            source: err,
        }
    }
}

impl SuperWrapperError {
    /// Add file path context to an error
    ///
    /// This method enriches an error with the file path where the operation
    /// failed, making debugging easier.
    pub fn context(mut self, path: &Path) -> Self {
        let path_str = path.to_string_lossy().to_string();
        match &mut self {
            SuperWrapperError::Io { path: p, .. } => *p = Some(path_str),
            SuperWrapperError::PdfParse { path: p, .. } => *p = Some(path_str),
            SuperWrapperError::Encrypted { path: p } => *p = Some(path_str),
            SuperWrapperError::PageOutOfRange { path: p, .. } => *p = Some(path_str),
            SuperWrapperError::Pdfium { path: p, .. } => *p = Some(path_str),
            _ => {}
        }
        self
    }

    /// Get the file path from an error, if available
    pub fn path(&self) -> Option<&str> {
        match self {
            SuperWrapperError::Io { path, .. } => path.as_deref(),
            SuperWrapperError::PdfParse { path, .. } => path.as_deref(),
            SuperWrapperError::Encrypted { path } => path.as_deref(),
            SuperWrapperError::PageOutOfRange { path, .. } => path.as_deref(),
            SuperWrapperError::Pdfium { path, .. } => path.as_deref(),
            _ => None,
        }
    }
}

/// Type alias for results using SuperWrapperError
pub type Result<T> = std::result::Result<T, SuperWrapperError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_context_io() {
        let error = SuperWrapperError::Io {
            path: None,
            source: std::io::Error::new(std::io::ErrorKind::NotFound, "file not found"),
        };

        let enriched = error.context(std::path::Path::new("/test/doc.pdf"));
        assert_eq!(enriched.path(), Some("/test/doc.pdf"));
    }

    #[test]
    fn test_error_context_pdf_parse() {
        let error = SuperWrapperError::PdfParse {
            path: None,
            details: "Invalid structure".to_string(),
        };

        let enriched = error.context(std::path::Path::new("/test/doc.pdf"));
        assert_eq!(enriched.path(), Some("/test/doc.pdf"));
    }

    #[test]
    fn test_error_display_with_path() {
        let error = SuperWrapperError::PdfParse {
            path: Some("/path/to/file.pdf".to_string()),
            details: "Invalid PDF header".to_string(),
        };

        let display = format!("{}", error);
        assert!(display.contains("Invalid PDF header"));
    }
}
