use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, ExtractionMode, ImageFormat, PdfEngine, VisualEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize the VisualEngine for PDF-to-image rendering
    let engine = VisualEngine;

    // Configure extraction for visual rendering (PNG format at 150 DPI)
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Png, // Could also use ImageFormat::Jpeg(80) for JPEG
        },
        ..Default::default()
    };

    // Extract visual content from a PDF file
    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== VisualEngine PDF-to-Image Rendering ===");
    println!("Total pages: {}", result.page_count);
    println!("Number of rendered images: {}", result.pages.len());

    // Show details for each rendered page
    for page in &result.pages {
        println!(
            "Page {}: {} characters of extracted text",
            page.page_number, page.char_count
        );
        // In a real application, you would save the image data here
        // For this example, we just confirm the page was processed
    }

    Ok(())
}
