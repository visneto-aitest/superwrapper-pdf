use crate::error::Result;
use crate::types::{ExtractionConfig, ExtractionResult};
use std::path::Path;

/// Trait implemented by all PDF extraction engines
pub trait PdfEngine: Send + Sync {
    /// Return the engine name for logging/error messages
    fn name(&self) -> &'static str;

    /// Extract content from a PDF file
    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult>;
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
