use pretty_assertions::assert_eq;
use std::io::{self, Write};
use std::path::PathBuf;
use superwrapper_pdf::engine::{FastEngine, PdfEngine};
use superwrapper_pdf::error::{Result, SuperWrapperError};
use superwrapper_pdf::types::ExtractionConfig;

#[test]
fn test_io_error() {
    let error: SuperWrapperError = io::Error::new(io::ErrorKind::NotFound, "file not found").into();

    assert!(matches!(error, SuperWrapperError::Io(_)));
}

#[test]
fn test_pdf_parse_error() {
    let error = SuperWrapperError::PdfParse("invalid PDF structure".to_string());
    assert!(matches!(error, SuperWrapperError::PdfParse(_)));
    assert_eq!(
        error.to_string(),
        "PDF parsing error: invalid PDF structure"
    );
}

#[test]
fn test_encrypted_error() {
    let error = SuperWrapperError::Encrypted;
    assert!(matches!(error, SuperWrapperError::Encrypted));
    assert_eq!(
        error.to_string(),
        "Encrypted PDF (no password provided or invalid)"
    );
}

#[test]
fn test_page_out_of_range_error() {
    let error = SuperWrapperError::PageOutOfRange {
        requested: 10,
        total: 5,
    };
    assert!(matches!(error, SuperWrapperError::PageOutOfRange { .. }));
    assert_eq!(error.to_string(), "Page 10 out of range (total: 5)");
}

#[test]
fn test_feature_not_enabled_error() {
    let error = SuperWrapperError::FeatureNotEnabled {
        mode: "Visual".to_string(),
        feature: "visual".to_string(),
    };
    assert!(matches!(error, SuperWrapperError::FeatureNotEnabled { .. }));
    assert_eq!(
        error.to_string(),
        "Extraction mode 'Visual' is not enabled. Build with feature 'visual' to enable it."
    );
}

#[test]
fn test_error_display() {
    let error = SuperWrapperError::PdfParse("test error".to_string());
    assert_eq!(format!("{}", error), "PDF parsing error: test error");
}

#[test]
fn test_error_from_io() {
    let io_err = io::Error::new(io::ErrorKind::PermissionDenied, "Access denied");
    let error: SuperWrapperError = io_err.into();
    assert!(matches!(error, SuperWrapperError::Io(_)));
}

#[test]
fn test_error_debug() {
    let error = SuperWrapperError::PdfParse("debug test".to_string());
    let debug_str = format!("{:?}", error);
    assert!(debug_str.contains("PdfParse"));
    assert!(debug_str.contains("debug test"));
}

#[test]
fn test_result_type_alias() {
    fn test_fn() -> Result<i32> {
        Ok(42)
    }

    let result = test_fn();
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
}

#[test]
fn test_result_error_conversion() {
    fn test_fn() -> Result<i32> {
        Err(SuperWrapperError::PdfParse("error".to_string()))
    }

    let result = test_fn();
    assert!(result.is_err());
}

#[test]
fn test_multiple_page_out_of_range_scenarios() {
    let error1 = SuperWrapperError::PageOutOfRange {
        requested: 0,
        total: 0,
    };
    let error2 = SuperWrapperError::PageOutOfRange {
        requested: 100,
        total: 10,
    };

    assert_eq!(error1.to_string(), "Page 0 out of range (total: 0)");
    assert_eq!(error2.to_string(), "Page 100 out of range (total: 10)");
}

#[test]
fn test_nonexistent_file_error() {
    let engine = FastEngine;
    let config = ExtractionConfig::default();
    let nonexistent = PathBuf::from("/nonexistent/path/to/file.pdf");

    let result = engine.extract(&nonexistent, &config);
    assert!(result.is_err());
}

#[test]
fn test_invalid_file_error() {
    let engine = FastEngine;
    let config = ExtractionConfig::default();
    let mut file = tempfile::NamedTempFile::new().unwrap();

    file.write_all(b"not a pdf").unwrap();
    file.flush().unwrap();

    let result = engine.extract(file.path(), &config);
    assert!(result.is_err());
}
