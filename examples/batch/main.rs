use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};
use walkdir::WalkDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let pdf_dir = Path::new("../../crates/superwrapper-pdf/tests/fixtures");
    let mut total_pages = 0u32;
    let mut file_count = 0u32;

    for entry in WalkDir::new(pdf_dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "pdf"))
    {
        let path = entry.path();
        match engine.extract(path, &config) {
            Ok(result) => {
                println!(
                    "Processed: {} - {} pages, {} chars",
                    path.display(),
                    result.page_count,
                    result.text.len()
                );
                total_pages += result.page_count;
                file_count += 1;
            }
            Err(e) => {
                eprintln!("Failed to process {}: {}", path.display(), e);
            }
        }
    }

    println!("=== Batch Processing Complete ===");
    println!("Files processed: {}", file_count);
    println!("Total pages: {}", total_pages);

    Ok(())
}
