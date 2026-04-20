use std::path::Path;
use superwrapper_pdf::{ExtractionConfig, FastEngine, PdfEngine, SuperWrapperError};

fn main() {
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let test_cases = vec![
        (
            "../../crates/superwrapper-pdf/tests/fixtures/sample.pdf",
            false,
        ),
        (
            "../../crates/superwrapper-pdf/tests/fixtures/nonexistent.pdf",
            false,
        ),
    ];

    for (path, should_succeed) in test_cases {
        let path = Path::new(path);
        println!("Testing: {}", path.display());

        match engine.extract(path, &config) {
            Ok(result) => {
                println!("  Success: {} pages", result.page_count);
                if !should_succeed {
                    println!("  WARNING: Expected failure but succeeded");
                }
            }
            Err(SuperWrapperError::Io { source, .. })
                if source.kind() == std::io::ErrorKind::NotFound =>
            {
                println!("  Expected error: File not found");
            }
            Err(SuperWrapperError::Encrypted { .. }) => {
                println!("  Error: Document is encrypted, try using password");
            }
            Err(e) => {
                println!("  Error: {:?}", e);
            }
        }
    }

    println!("=== Error Handling Complete ===");
}
