//! SuperWrapper-PDF: A unified PDF extraction and conversion library

pub mod engine;
pub mod error;
pub mod types;

#[cfg(feature = "visual")]
pub use engine::VisualEngine;
pub use engine::{FastEngine, PdfEngine, StructuredEngine};
pub use error::{Result, SuperWrapperError};
pub use types::{ExtractionConfig, ExtractionMode, ExtractionResult, ImageFormat, PageInfo};
