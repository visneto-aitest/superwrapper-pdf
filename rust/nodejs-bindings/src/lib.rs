use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::path::PathBuf;

use superwrapper_pdf::{
    ExtractionConfig, ExtractionMode, FastEngine, ImageFormat, PdfEngine, StructuredEngine,
    VisualEngine,
};

/// Page information from extraction
#[napi(object)]
pub struct PageInfo {
    pub page_number: u32,
    pub text: String,
    pub char_count: u32,
}

/// Result of PDF extraction
#[napi(object)]
pub struct ExtractionResult {
    pub text: String,
    pub markdown: String,
    pub page_count: u32,
    pub pages: Vec<PageInfo>,
    pub source: Option<String>,
}

impl From<superwrapper_pdf::ExtractionResult> for ExtractionResult {
    fn from(r: superwrapper_pdf::ExtractionResult) -> Self {
        Self {
            text: r.text,
            markdown: r.markdown,
            page_count: r.page_count,
            pages: r
                .pages
                .into_iter()
                .map(|p| PageInfo {
                    page_number: p.page_number,
                    text: p.text,
                    char_count: p.char_count as u32,
                })
                .collect(),
            source: r.source.map(|s| s.to_string_lossy().to_string()),
        }
    }
}

/// Extract PDF content using fast mode (default)
#[napi]
pub fn extract(path: String) -> Result<ExtractionResult> {
    let path_buf = PathBuf::from(&path);
    let config = ExtractionConfig::default();
    let engine: Box<dyn PdfEngine> = Box::new(FastEngine);

    let result = engine.extract(&path_buf, &config).map_err(|e| {
        Error::new(
            napi::Status::GenericFailure,
            format!("Extraction failed: {}", e),
        )
    })?;

    Ok(result.into())
}

/// Extract PDF content using structured mode (markdown output)
#[napi]
pub fn extract_structured(path: String) -> Result<ExtractionResult> {
    let path_buf = PathBuf::from(&path);
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        ..Default::default()
    };
    let engine: Box<dyn PdfEngine> = Box::new(StructuredEngine);

    let result = engine.extract(&path_buf, &config).map_err(|e| {
        Error::new(
            napi::Status::GenericFailure,
            format!("Extraction failed: {}", e),
        )
    })?;

    Ok(result.into())
}

/// Extract PDF content using visual mode (returns text from rendered pages)
#[napi]
pub fn extract_visual(path: String, dpi: Option<u32>) -> Result<ExtractionResult> {
    let path_buf = PathBuf::from(&path);
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: dpi.unwrap_or(150),
            format: ImageFormat::Png,
        },
        ..Default::default()
    };
    let engine: Box<dyn PdfEngine> = Box::new(VisualEngine);

    let result = engine.extract(&path_buf, &config).map_err(|e| {
        Error::new(
            napi::Status::GenericFailure,
            format!("Extraction failed: {}", e),
        )
    })?;

    Ok(result.into())
}
