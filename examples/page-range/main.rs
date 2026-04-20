use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;

    let config = ExtractionConfig {
        page_range: Some(0..=2),
        ..Default::default()
    };

    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== Page Range Extraction ===");
    println!("Total pages extracted: {}", result.page_count);
    println!("Page range: 0-2 (first 3 pages)");

    for page in &result.pages {
        println!("Page {}: {} characters", page.page_number, page.char_count);
    }

    Ok(())
}
