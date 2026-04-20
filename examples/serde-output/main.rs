use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(
        Path::new("../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"),
        &config,
    )?;

    let json = serde_json::to_string_pretty(&result)?;
    println!("=== JSON Output ===");
    println!("{}", json);

    Ok(())
}
