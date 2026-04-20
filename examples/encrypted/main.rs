use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;

    let config = ExtractionConfig {
        password: Some("secret".to_string()),
        ..Default::default()
    };

    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/encrypted.pdf"),
        &config,
    )?;

    println!("=== Encrypted PDF Extraction ===");
    println!("Total pages: {}", result.page_count);
    println!("Extracted text length: {} characters", result.text.len());

    Ok(())
}
