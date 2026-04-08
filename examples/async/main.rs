use std::path::Path;
use superwrapper_pdf::{PdfEngine, ExtractionConfig, ExtractionMode};
use tokio::task;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("=== Async PDF Processing Examples ===");
    
    // Example 1: Concurrent FastEngine processing
    let fast_future = task::spawn(async {
        let engine = superwrapper_pdf::FastEngine;
        let config = ExtractionConfig::default();
        engine.extract(Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"), &config)
    });
    
    // Example 2: Concurrent StructuredEngine processing
    let structured_future = task::spawn(async {
        let engine = superwrapper_pdf::StructuredEngine;
        let config = ExtractionConfig {
            mode: ExtractionMode::Structured,
            parallel: true,
            ..Default::default()
        };
        engine.extract(Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"), &config)
    });
    
    // Example 3: Concurrent VisualEngine processing
    let visual_future = task::spawn(async {
        let engine = superwrapper_pdf::VisualEngine;
        let config = ExtractionConfig {
            mode: ExtractionMode::Visual { 
                dpi: 150,
                format: superwrapper_pdf::ImageFormat::Png,
            },
            ..Default::default()
        };
        engine.extract(Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"), &config)
    });
    
    // Wait for all extractions to complete
    let fast_result = fast_future.await??;
    let structured_result = structured_future.await??;
    let visual_result = visual_future.await??;
    
    println!("FastEngine: {} pages, {} chars text", 
             fast_result.page_count, fast_result.text.len());
    println!("StructuredEngine: {} pages, {} chars markdown", 
             structured_result.page_count, structured_result.markdown.len());
    println!("VisualEngine: {} pages, {} chars text (from images)", 
             visual_result.page_count, visual_result.text.len());
    
    Ok(())
}