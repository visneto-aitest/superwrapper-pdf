use std::path::Path;
use std::sync::Arc;
use superwrapper_pdf::{
    ExtractionConfig, ExtractionProgress, FastEngine, PdfEngine, ProgressCallback,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;

    let progress_callback: ProgressCallback = Arc::new(|progress: &ExtractionProgress| {
        println!(
            "Progress: Page {}/{} ({}%) - {} bytes",
            progress.current_page,
            progress.total_pages,
            progress.percent_complete.round(),
            progress.bytes_processed
        );
    });

    let config = ExtractionConfig {
        progress_callback: Some(progress_callback),
        ..Default::default()
    };

    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    println!("=== Progress Extraction Complete ===");
    println!("Total pages: {}", result.page_count);
    println!("Final text length: {} characters", result.text.len());

    Ok(())
}
