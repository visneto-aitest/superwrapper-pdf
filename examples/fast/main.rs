use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize the FastEngine for high-speed text extraction
    let engine = FastEngine;

    // Configure extraction (using defaults for fast text extraction)
    let config = ExtractionConfig::default();

    // Extract text from a PDF file
    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== FastEngine Text Extraction ===");
    println!("Total pages: {}", result.page_count);
    println!("Extracted text length: {} characters", result.text.len());
    println!("First 500 characters:");
    println!("{}", &result.text[..500.min(result.text.len())]);

    // Show per-page breakdown
    for page in &result.pages {
        println!("Page {}: {} characters", page.page_number, page.char_count);
    }

    Ok(())
}
