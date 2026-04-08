use pretty_assertions::assert_eq;
use superwrapper_pdf::engine::{FastEngine, PdfEngine, StructuredEngine, VisualEngine};
use superwrapper_pdf::types::{ExtractionConfig, ExtractionMode, ImageFormat};

fn sample_pdf() -> std::path::PathBuf {
    FastEngine::fixture_pdf("sample.pdf")
}

fn minimal_pdf() -> std::path::PathBuf {
    FastEngine::fixture_pdf("minimal.pdf")
}

#[test]
fn test_fast_engine_can_be_created() {
    let engine = FastEngine;
    assert_eq!(engine.name(), "FastEngine");
}

#[test]
fn test_structured_engine_can_be_created() {
    let engine = StructuredEngine;
    assert_eq!(engine.name(), "StructuredEngine");
}

#[test]
fn test_visual_engine_can_be_created() {
    let engine = VisualEngine;
    assert_eq!(engine.name(), "VisualEngine");
}

#[test]
fn test_fast_extraction() {
    let path = sample_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_structured_extraction() {
    let path = sample_pdf();
    let engine = StructuredEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
    assert!(!result.text.is_empty());
}

#[test]
fn test_visual_extraction() {
    let path = sample_pdf();
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_parallel_extraction() {
    let path = sample_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig {
        parallel: true,
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_page_range_extraction() {
    let path = sample_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig {
        page_range: Some(0..=0),
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.pages.len() >= 1);
}

#[test]
fn test_result_contains_source_path() {
    let path = sample_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.source.is_some());
}

#[test]
fn test_all_engines_implement_trait() {
    let engines: Vec<Box<dyn PdfEngine>> = vec![
        Box::new(FastEngine),
        Box::new(StructuredEngine),
        Box::new(VisualEngine),
    ];

    for engine in engines {
        let _name = engine.name();
    }
}

#[test]
fn test_multipage_extraction() {
    let path = sample_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
    assert_eq!(result.pages.len() as u32, result.page_count);
}

#[test]
fn test_visual_jpeg_format() {
    let path = sample_pdf();
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Jpeg(80),
        },
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_structured_parallel() {
    let path = sample_pdf();
    let engine = StructuredEngine;
    let config = ExtractionConfig {
        parallel: true,
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_visual_multipage() {
    let path = sample_pdf();
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_minimal_pdf_fast() {
    let path = minimal_pdf();
    let engine = FastEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_minimal_pdf_structured() {
    let path = minimal_pdf();
    let engine = StructuredEngine;
    let config = ExtractionConfig::default();

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}

#[test]
fn test_minimal_pdf_visual() {
    let path = minimal_pdf();
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };

    let result = engine.extract(&path, &config).unwrap();

    assert!(result.page_count > 0);
}
