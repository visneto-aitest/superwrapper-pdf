use pretty_assertions::assert_eq;
use std::io::{self, Write};
use std::path::PathBuf;
use superwrapper_pdf::engine::{FastEngine, PdfEngine};
use superwrapper_pdf::error::{Result, SuperWrapperError};
use superwrapper_pdf::types::ExtractionConfig;

#[test]
fn test_io_error() {
    let error: SuperWrapperError = io::Error::new(io::ErrorKind::NotFound, "file not found").into();

    assert!(matches!(
        error,
        SuperWrapperError::Io { path: _, source: _ }
    ));
}

#[test]
fn test_pdf_parse_error() {
    let error = SuperWrapperError::PdfParse {
        path: None,
        details: "invalid PDF structure".to_string(),
    };
    assert!(matches!(error, SuperWrapperError::PdfParse { .. }));
    assert_eq!(
        error.to_string(),
        "PDF parsing error: invalid PDF structure"
    );
}

#[test]
fn test_encrypted_error() {
    let error = SuperWrapperError::Encrypted { path: None };
    assert!(matches!(error, SuperWrapperError::Encrypted { .. }));
    assert_eq!(error.to_string(), "Encrypted PDF (password required)");
}

#[test]
fn test_page_out_of_range_error() {
    let error = SuperWrapperError::PageOutOfRange {
        requested: 10,
        total: 5,
        path: None,
    };
    assert!(matches!(error, SuperWrapperError::PageOutOfRange { .. }));
    assert_eq!(
        error.to_string(),
        "Page 10 out of range (document has 5 pages)"
    );
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
        "Extraction mode 'Visual' is not enabled. Add feature 'visual' to Cargo.toml to enable."
    );
}

#[test]
fn test_error_display() {
    let error = SuperWrapperError::PdfParse {
        path: None,
        details: "test error".to_string(),
    };
    assert_eq!(format!("{}", error), "PDF parsing error: test error");
}

#[test]
fn test_error_from_io() {
    let io_err = io::Error::new(io::ErrorKind::PermissionDenied, "Access denied");
    let error: SuperWrapperError = io_err.into();
    assert!(matches!(
        error,
        SuperWrapperError::Io { path: _, source: _ }
    ));
}

#[test]
fn test_error_debug() {
    let error = SuperWrapperError::PdfParse {
        path: None,
        details: "debug test".to_string(),
    };
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
        Err(SuperWrapperError::PdfParse {
            path: None,
            details: "error".to_string(),
        })
    }

    let result = test_fn();
    assert!(result.is_err());
}

#[test]
fn test_multiple_page_out_of_range_scenarios() {
    let error1 = SuperWrapperError::PageOutOfRange {
        requested: 0,
        total: 0,
        path: None,
    };
    let error2 = SuperWrapperError::PageOutOfRange {
        requested: 100,
        total: 10,
        path: None,
    };

    assert_eq!(
        error1.to_string(),
        "Page 0 out of range (document has 0 pages)"
    );
    assert_eq!(
        error2.to_string(),
        "Page 100 out of range (document has 10 pages)"
    );
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

#[test]
fn test_error_path() {
    let error = SuperWrapperError::PdfParse {
        path: Some("/path/to/file.pdf".to_string()),
        details: "error".to_string(),
    };
    assert_eq!(error.path(), Some("/path/to/file.pdf"));
}

#[test]
fn test_error_context() {
    let error = SuperWrapperError::PdfParse {
        path: None,
        details: "error".to_string(),
    }
    .context(std::path::Path::new("/test/file.pdf"));

    assert_eq!(error.path(), Some("/test/file.pdf"));
}
