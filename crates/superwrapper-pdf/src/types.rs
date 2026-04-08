//! Core types for PDF extraction configuration and results
//!
//! This module defines the fundamental data structures used throughout the library:
//! - [`ExtractionConfig`]: Configuration for extraction operations
//! - [`ExtractionMode`]: Selection of which extraction engine to use
//! - [`ExtractionResult`]: Output from successful extraction operations
//! - [`PageInfo`]: Per-page metadata from extraction
//! - [`ImageFormat`]: Output format options for visual rendering

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Complete result of a PDF extraction operation
///
/// This struct contains all the output from a successful PDF extraction, including:
/// - Plain text content (always available)
/// - Markdown content (available when using StructuredEngine)
/// - Page count and per-page metadata
/// - Source file path
///
/// # Example
///
/// ```rust,no_run
/// use superwrapper_pdf::{FastEngine, PdfEngine, ExtractionConfig};
/// use std::path::Path;
///
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let engine = FastEngine;
/// let result = engine.extract(Path::new("document.pdf"), &Default::default())?;
///
/// println!("Pages: {}", result.page_count);
/// println!("Characters: {}", result.text.len());
/// for page in &result.pages {
///     println!("Page {}: {} chars", page.page_number, page.char_count);
/// }
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    /// Extracted markdown content (when using StructuredEngine)
    /// Empty string when using other engines
    pub markdown: String,
    /// Raw plain text content extracted from all pages
    pub text: String,
    /// Total number of pages in the source PDF
    pub page_count: u32,
    /// Per-page metadata including text content and character counts
    pub pages: Vec<PageInfo>,
    /// Source file path if extracted from a file
    pub source: Option<PathBuf>,
}

/// Metadata for a single extracted page
///
/// Contains detailed information about each page in the extracted PDF.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    /// 1-indexed page number (first page is 1, not 0)
    pub page_number: u32,
    /// Full text content of this specific page
    pub text: String,
    /// Number of characters in this page's text content
    pub char_count: usize,
}

/// Configuration for an extraction operation
///
/// Controls how PDF extraction is performed, including:
/// - Which extraction engine to use
/// - Page range selection
/// - Password for encrypted PDFs
/// - Parallel processing options
///
/// # Example
///
/// ```rust
/// use superwrapper_pdf::{ExtractionConfig, ExtractionMode, ImageFormat};
///
/// // Basic configuration with defaults
/// let config = ExtractionConfig::default();
///
/// // Custom configuration for visual extraction
/// let visual_config = ExtractionConfig {
///     mode: ExtractionMode::Visual {
///         dpi: 300,
///         format: ImageFormat::Png,
///     },
///     page_range: Some(0..=5),  // First 6 pages (0-indexed)
///     password: Some("secret".to_string()),  // For encrypted PDFs
///     parallel: true,  // Enable parallel processing
/// };
/// ```
#[derive(Debug, Clone, Default)]
pub struct ExtractionConfig {
    /// Which extraction engine/mode to use
    /// Default: [`ExtractionMode::Fast`]
    pub mode: ExtractionMode,
    /// Optional page range to extract (0-indexed inclusive)
    /// Example: `Some(0..=5)` extracts pages 1-6
    /// Default: None (all pages)
    pub page_range: Option<std::ops::RangeInclusive<u32>>,
    /// Password for encrypted/password-protected PDFs
    /// Default: None (document is not encrypted)
    pub password: Option<String>,
    /// Enable parallel processing where supported
    /// When true, uses rayon for parallel page extraction
    /// Default: false
    pub parallel: bool,
}

/// Extraction mode determines which backend engine is used
///
/// Each variant selects a different extraction strategy optimized for specific use cases.
///
/// | Mode | Engine | Best For |
/// |------|--------|----------|
/// | Fast | FastEngine | High-speed text extraction |
/// | Structured | StructuredEngine | Markdown conversion |
/// | Visual | VisualEngine | PDF-to-image rendering |
///
/// # Visual Mode Options
///
/// When using [`ExtractionMode::Visual`], configure rendering options:
///
/// ```rust
/// use superwrapper_pdf::{ExtractionMode, ImageFormat};
///
/// // High-quality image rendering
/// let config = ExtractionMode::Visual {
///     dpi: 300,  // 300 DPI for print quality
///     format: ImageFormat::Png,  // Lossless PNG
/// };
///
/// // Compressed JPEG for web
/// let web_config = ExtractionMode::Visual {
///     dpi: 150,
///     format: ImageFormat::Jpeg(80),  // 80% quality
/// };
/// ```
#[derive(Debug, Clone, PartialEq, Default)]
pub enum ExtractionMode {
    /// Fast text extraction using pdf_oxide
    /// Optimized for raw speed with minimal memory usage
    /// No additional dependencies required
    #[default]
    Fast,
    /// Structured markdown/JSON extraction using unpdf
    /// Extracts content as formatted markdown with layout preservation
    /// Requires `structured` feature to be enabled
    Structured,
    /// Visual rendering to images using pdfium-render
    /// Renders each page as an image (PNG or JPEG)
    /// Requires `visual` feature and system pdfium library
    Visual {
        /// Resolution for rendered images in dots per inch
        /// Common values: 72 (screen), 150 (draft), 300 (print)
        /// Higher values produce larger, sharper images
        dpi: u32,
        /// Output image format
        format: ImageFormat,
    },
}

/// Output image format for visual extraction
///
/// Controls the format and quality of images produced by VisualEngine.
#[derive(Debug, Clone, PartialEq)]
pub enum ImageFormat {
    /// PNG format - lossless compression, supports transparency
    /// Best for: High-quality output, diagrams, documents
    Png,
    /// JPEG format with quality setting (0-100)
    /// Higher values produce larger files with better quality
    /// Best for: Photographs, web use, storage-constrained environments
    Jpeg(u8),
}

impl ImageFormat {
    /// Convert to the image crate's format enum
    #[cfg(feature = "visual")]
    pub fn to_image_format(&self) -> image::ImageFormat {
        match self {
            ImageFormat::Png => image::ImageFormat::Png,
            ImageFormat::Jpeg(_) => image::ImageFormat::Jpeg,
        }
    }
}
