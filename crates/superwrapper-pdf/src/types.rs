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
use std::sync::Arc;

/// Progress information for extraction operations
#[derive(Debug, Clone)]
pub struct ExtractionProgress {
    /// Current page being processed (1-indexed)
    pub current_page: u32,
    /// Total number of pages
    pub total_pages: u32,
    /// Percentage complete (0-100)
    pub percent_complete: f32,
    /// Estimated bytes processed for current page
    pub bytes_processed: u64,
    /// Total bytes in the document
    pub total_bytes: u64,
}

impl ExtractionProgress {
    pub fn new(
        current_page: u32,
        total_pages: u32,
        bytes_processed: u64,
        total_bytes: u64,
    ) -> Self {
        let percent_complete = if total_pages > 0 {
            ((current_page as f32 / total_pages as f32) * 100.0).min(100.0)
        } else {
            0.0
        };
        Self {
            current_page,
            total_pages,
            percent_complete,
            bytes_processed,
            total_bytes,
        }
    }
}

/// Callback for progress updates during extraction
///
/// # Example
///
/// ```rust
/// use superwrapper_pdf::ExtractionProgress;
///
/// fn progress_handler(progress: &ExtractionProgress) {
///     println!("Processing page {}/{} ({}%)",
///         progress.current_page,
///         progress.total_pages,
///         progress.percent_complete.round());
/// }
/// ```
pub type ProgressCallback = Arc<dyn Fn(&ExtractionProgress) + Send + Sync>;

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

/// Chunk of extracted pages from streaming extraction
///
/// Returned during streaming extraction, containing a batch of pages
/// and metadata about the extraction progress.
#[derive(Debug, Clone)]
pub struct ExtractionChunk {
    /// Pages extracted in this chunk
    pub pages: Vec<PageInfo>,
    /// Starting page number of this chunk (1-indexed)
    pub start_page: u32,
    /// Ending page number of this chunk (1-indexed)
    pub end_page: u32,
    /// Whether this is the final chunk
    pub is_complete: bool,
}

impl ExtractionChunk {
    pub fn new(pages: Vec<PageInfo>, start_page: u32, end_page: u32, is_complete: bool) -> Self {
        Self {
            pages,
            start_page,
            end_page,
            is_complete,
        }
    }

    pub fn into_result(self, total_pages: u32, source: Option<PathBuf>) -> ExtractionResult {
        let text = self
            .pages
            .iter()
            .map(|p| p.text.as_str())
            .collect::<Vec<_>>()
            .join("\n\n");
        let markdown = text.to_string();
        ExtractionResult {
            text,
            markdown,
            page_count: total_pages,
            pages: self.pages,
            source,
        }
    }
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
///     progress_callback: None,
///     streaming: false,
///     chunk_size: None,
/// };
/// ```
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
    /// Callback for progress updates during extraction
    /// Progress callback fires at least once per 1000 pages processed
    /// Default: None (no progress reporting)
    pub progress_callback: Option<ProgressCallback>,
    /// Enable streaming mode for large PDFs
    /// When enabled, processes pages incrementally to reduce memory usage
    /// Default: false
    pub streaming: bool,
    /// Chunk size for streaming mode (number of pages per chunk)
    /// Only used when streaming is true
    /// Default: 50
    pub chunk_size: Option<usize>,
}

impl Default for ExtractionConfig {
    fn default() -> Self {
        Self {
            mode: ExtractionMode::default(),
            page_range: None,
            password: None,
            parallel: false,
            progress_callback: None,
            streaming: false,
            chunk_size: None,
        }
    }
}

impl Clone for ExtractionConfig {
    fn clone(&self) -> Self {
        Self {
            mode: self.mode.clone(),
            page_range: self.page_range.clone(),
            password: self.password.clone(),
            parallel: self.parallel,
            progress_callback: None,
            streaming: self.streaming,
            chunk_size: self.chunk_size,
        }
    }
}

impl std::fmt::Debug for ExtractionConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ExtractionConfig")
            .field("mode", &self.mode)
            .field("page_range", &self.page_range)
            .field("password", &self.password.as_ref().map(|_| "***"))
            .field("parallel", &self.parallel)
            .field("progress_callback", &self.progress_callback.is_some())
            .field("streaming", &self.streaming)
            .field("chunk_size", &self.chunk_size)
            .finish()
    }
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
