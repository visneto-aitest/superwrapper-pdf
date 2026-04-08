//! PDF extraction engines and core trait definitions
//!
//! This module defines the [`PdfEngine`] trait that all PDF extraction engines implement,
//! along with implementations for each specialized engine:
//!
//! - [`FastEngine`]: High-speed text extraction using `pdf_oxide`
//! - [`StructuredEngine`]: Markdown/structured content extraction using `unpdf` (feature-gated)
//! - [`VisualEngine`]: Visual rendering to images using `pdfium-render` (feature-gated)
//!
//! # Engine Selection Guide
//!
//! Choose an engine based on your use case:
//!
//! | Engine | Speed | Output | Memory | Dependencies |
//! |--------|-------|--------|--------|--------------|
//! | Fast | ⚡⚡⚡ | Plain text | Low | None |
//! | Structured | ⚡⚡ | Markdown | Medium | `unpdf` |
//! | Visual | ⚡ | Images + text | High | `pdfium-render` |
//!
//! # Concurrency Support
//!
//! All engines implement [`Send`] and [`Sync`] and can be safely shared between threads.
//! When the `async` feature is enabled, engines also provide asynchronous extraction
//! methods that integrate with Tokio's runtime.

use crate::error::Result;
use crate::types::{ExtractionConfig, ExtractionResult};
use std::path::Path;

/// Trait implemented by all PDF extraction engines
///
/// This trait defines the common interface for PDF extraction. Each engine implements
/// this trait to provide specialized extraction capabilities.
///
/// # Example
///
/// ```rust,no_run
/// use superwrapper_pdf::{PdfEngine, FastEngine, ExtractionConfig};
/// use std::path::Path;
///
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let engine = FastEngine;
/// let config = ExtractionConfig::default();
/// let result = engine.extract(Path::new("document.pdf"), &config)?;
/// # Ok(())
/// # }
/// ```
pub trait PdfEngine: Send + Sync {
    /// Return the engine name for logging/error messages
    ///
    /// This method identifies which engine is being used, primarily for debugging
    /// and error reporting purposes.
    ///
    /// # Example
    ///
    /// ```
    /// use superwrapper_pdf::FastEngine;
    /// use superwrapper_pdf::engine::PdfEngine;
    ///
    /// let engine = FastEngine;
    /// assert_eq!(engine.name(), "FastEngine");
    /// ```
    fn name(&self) -> &'static str;

    /// Extract content from a PDF file
    ///
    /// This is the primary method for performing PDF extraction. It takes a file path
    /// and configuration and returns structured extraction results.
    ///
    /// # Arguments
    ///
    /// * `path` - Path to the PDF file to extract
    /// * `config` - Configuration controlling extraction behavior
    ///
    /// # Returns
    ///
    /// An [`ExtractionResult`] containing the extracted content and metadata.
    ///
    /// # Errors
    ///
    /// Returns a [`SuperWrapperError`](crate::SuperWrapperError) if extraction fails.
    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult>;

    /// Extract content from a PDF file asynchronously
    ///
    /// This method provides asynchronous extraction capabilities when the `async`
    /// feature is enabled. By default, it falls back to synchronous extraction.
    ///
    /// # Arguments
    ///
    /// * `path` - Path to the PDF file to extract
    /// * `config` - Configuration controlling extraction behavior
    ///
    /// # Returns
    ///
    /// An [`ExtractionResult`] containing the extracted content and metadata.
    ///
    /// # Errors
    ///
    /// Returns a [`SuperWrapperError`](crate::SuperWrapperError) if extraction fails.
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// use superwrapper_pdf::{PdfEngine, FastEngine, ExtractionConfig};
    /// use std::path::Path;
    ///
    /// # #[cfg(feature = "async")]
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let engine = FastEngine;
    /// let config = ExtractionConfig::default();
    /// let result = engine.extract_async(Path::new("document.pdf"), &config)?;
    /// # Ok(())
    /// # }
    /// ```
    #[cfg(feature = "async")]
    fn extract_async(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult> {
        // Default implementation falls back to sync extraction
        self.extract(path, config)
    }
}

// Engine modules (feature-gated)
mod fast;
#[cfg(feature = "structured")]
mod structured;
#[cfg(feature = "visual")]
mod visual;

pub use fast::FastEngine;
#[cfg(feature = "structured")]
pub use structured::StructuredEngine;
#[cfg(feature = "visual")]
pub use visual::VisualEngine;
