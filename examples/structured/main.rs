use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, ExtractionMode, PdfEngine, StructuredEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize the StructuredEngine for markdown conversion
    let engine = StructuredEngine;

    // Configure extraction for structured/markdown output with parallel processing
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        parallel: true, // Enable parallel extraction for better performance
        ..Default::default()
    };

    // Extract structured content from a PDF file
    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== StructuredEngine Markdown Extraction ===");
    println!("Total pages: {}", result.page_count);
    println!(
        "Markdown content length: {} characters",
        result.markdown.len()
    );
    println!("First 1000 characters of markdown:");
    println!("{}", &result.markdown[..1000.min(result.markdown.len())]);

    // Also get plain text if needed
    println!("\nPlain text length: {} characters", result.text.len());

    Ok(())
}
