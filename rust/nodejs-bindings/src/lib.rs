use napi::bindgen_prelude::*;
use std::path::PathBuf;

use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

/// Extract PDF content
#[napi]
pub fn extract(path: String) -> Result<Object> {
    let path_buf = PathBuf::from(&path);
    let config = ExtractionConfig::default();
    let engine: Box<dyn PdfEngine> = Box::new(FastEngine);

    // Extract
    let result = engine
        .extract(&path_buf, &config)
        .map_err(|e| Error::new(Status::GenericFailure, format!("Extraction failed: {}", e)))?;

    // Convert to JavaScript object
    let mut obj = Object::new();

    // Add text
    obj.set("text", result.text)?;

    // Add markdown
    obj.set("markdown", result.markdown)?;

    // Add page count
    obj.set("pageCount", result.page_count)?;

    // Add pages array
    let pages_array = Array::new();
    for (i, page) in result.pages.into_iter().enumerate() {
        let mut page_obj = Object::new();
        page_obj.set("pageNumber", page.page_number)?;
        page_obj.set("text", page.text)?;
        page_obj.set("charCount", page.char_count)?;
        pages_array.set_element(i as u32, page_obj)?;
    }
    obj.set("pages", pages_array)?;

    // Add source (optional)
    if let Some(source) = result.source {
        obj.set("source", source.to_string_lossy().to_string())?;
    }

    Ok(obj)
}
