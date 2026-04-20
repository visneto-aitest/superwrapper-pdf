use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;

    let config = ExtractionConfig {
        streaming: true,
        chunk_size: Some(25),
        ..Default::default()
    };

    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== Streaming Extraction ===");
    println!("Total pages: {}", result.page_count);
    println!("Extracted text length: {} characters", result.text.len());
    println!("Chunks processed: {}", result.pages.len() / 25 + 1);

    Ok(())
}
