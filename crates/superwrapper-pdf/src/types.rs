use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Complete result of a PDF extraction operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    /// Extracted markdown content (when available)
    pub markdown: String,
    /// Raw plain text (always present)
    pub text: String,
    /// Total number of pages in the source PDF
    pub page_count: u32,
    /// Per-page metadata
    pub pages: Vec<PageInfo>,
    /// Source file path (if extracted from a file)
    pub source: Option<PathBuf>,
}

/// Metadata for a single extracted page
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    /// 1-indexed page number
    pub page_number: u32,
    /// Full text content of this page
    pub text: String,
    /// Character count of the page text
    pub char_count: usize,
}

/// Configuration for an extraction operation
#[derive(Debug, Clone, Default)]
pub struct ExtractionConfig {
    /// Which extraction engine to use
    pub mode: ExtractionMode,
    /// Optional page range (0-indexed inclusive range)
    pub page_range: Option<std::ops::RangeInclusive<u32>>,
    /// Password for encrypted PDFs
    pub password: Option<String>,
    /// Enable parallel processing (where supported)
    pub parallel: bool,
}

/// Extraction mode determines which backend engine is used
#[derive(Debug, Clone, PartialEq, Default)]
pub enum ExtractionMode {
    /// Fast text extraction using pdf_oxide (default)
    #[default]
    Fast,
    /// Structured markdown/JSON extraction using unpdf
    Structured,
    /// Visual rendering using pdfium-render (produces images)
    Visual {
        /// DPI for rendered images (e.g., 150, 300)
        dpi: u32,
        /// Output image format
        format: ImageFormat,
    },
}

/// Output image format for visual extraction
#[derive(Debug, Clone, PartialEq)]
pub enum ImageFormat {
    Png,
    Jpeg(u8), // quality 0-100
}

impl ImageFormat {
    #[cfg(feature = "visual")]
    pub fn to_image_format(&self) -> image::ImageFormat {
        match self {
            ImageFormat::Png => image::ImageFormat::Png,
            ImageFormat::Jpeg(_) => image::ImageFormat::Jpeg,
        }
    }
}
