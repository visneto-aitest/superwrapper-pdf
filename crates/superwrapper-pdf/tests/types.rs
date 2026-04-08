use pretty_assertions::assert_eq;
use serde_json;
use superwrapper_pdf::types::{
    ExtractionConfig, ExtractionMode, ExtractionResult, ImageFormat, PageInfo,
};

#[test]
fn test_extraction_config_default() {
    let config = ExtractionConfig::default();
    assert_eq!(config.mode, ExtractionMode::Fast);
    assert_eq!(config.page_range, None);
    assert_eq!(config.password, None);
    assert!(!config.parallel);
}

#[test]
fn test_extraction_config_with_mode() {
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        ..Default::default()
    };
    assert_eq!(config.mode, ExtractionMode::Structured);
}

#[test]
fn test_extraction_config_with_visual_mode() {
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 300,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };
    if let ExtractionMode::Visual { dpi, format } = &config.mode {
        assert_eq!(*dpi, 300);
        assert_eq!(*format, ImageFormat::Png);
    } else {
        panic!("Expected Visual mode");
    }
}

#[test]
fn test_extraction_config_with_page_range() {
    let config = ExtractionConfig {
        page_range: Some(0..=5),
        ..Default::default()
    };
    assert!(config.page_range.is_some());
    let range = config.page_range.unwrap();
    assert_eq!(*range.start(), 0);
    assert_eq!(*range.end(), 5);
}

#[test]
fn test_extraction_config_with_password() {
    let config = ExtractionConfig {
        password: Some("secret".to_string()),
        ..Default::default()
    };
    assert!(config.password.is_some());
    assert_eq!(config.password.unwrap(), "secret");
}

#[test]
fn test_extraction_config_with_parallel() {
    let config = ExtractionConfig {
        parallel: true,
        ..Default::default()
    };
    assert!(config.parallel);
}

#[test]
fn test_extraction_result_serialization() {
    let result = ExtractionResult {
        markdown: "# Title".to_string(),
        text: "Title".to_string(),
        page_count: 1,
        pages: vec![PageInfo {
            page_number: 1,
            text: "Title".to_string(),
            char_count: 5,
        }],
        source: Some("/path/to/file.pdf".into()),
    };

    let json = serde_json::to_string(&result).unwrap();
    assert!(json.contains("Title"));
    assert!(json.contains("page_count"));
    assert!(json.contains("1"));
}

#[test]
fn test_extraction_result_deserialization() {
    let json = r#"{"markdown":"Hello","text":"Hello","page_count":1,"pages":[{"page_number":1,"text":"Hello","char_count":5}],"source":"/path/to/file.pdf"}"#;

    let result: ExtractionResult = serde_json::from_str(json).unwrap();
    assert_eq!(result.page_count, 1);
    assert_eq!(result.pages.len(), 1);
    assert_eq!(result.pages[0].page_number, 1);
}

#[test]
fn test_page_info_serialization() {
    let page = PageInfo {
        page_number: 1,
        text: "Test content".to_string(),
        char_count: 12,
    };

    let json = serde_json::to_string(&page).unwrap();
    assert!(json.contains("page_number"));
    assert!(json.contains("1"));
    assert!(json.contains("Test content"));
}

#[test]
fn test_image_format_png() {
    let format = ImageFormat::Png;
    assert_eq!(format.to_image_format(), image::ImageFormat::Png);
}

#[test]
fn test_image_format_jpeg() {
    let format = ImageFormat::Jpeg(80);
    assert_eq!(format.to_image_format(), image::ImageFormat::Jpeg);
}

#[test]
fn test_image_format_clone() {
    let format = ImageFormat::Jpeg(90);
    let cloned = format.clone();
    assert_eq!(format.to_image_format(), cloned.to_image_format());
}

#[test]
fn test_extraction_mode_fast() {
    let mode = ExtractionMode::Fast;
    assert!(matches!(mode, ExtractionMode::Fast));
}

#[test]
fn test_extraction_mode_structured() {
    let mode = ExtractionMode::Structured;
    assert!(matches!(mode, ExtractionMode::Structured));
}

#[test]
fn test_extraction_mode_visual() {
    let mode = ExtractionMode::Visual {
        dpi: 150,
        format: ImageFormat::Jpeg(75),
    };
    if let ExtractionMode::Visual { dpi, format } = mode {
        assert_eq!(dpi, 150);
        if let ImageFormat::Jpeg(q) = format {
            assert_eq!(q, 75);
        }
    }
}

#[test]
fn test_page_info_debug() {
    let page = PageInfo {
        page_number: 42,
        text: "test".to_string(),
        char_count: 4,
    };
    let debug_str = format!("{:?}", page);
    assert!(debug_str.contains("42"));
    assert!(debug_str.contains("test"));
}

#[test]
fn test_extraction_result_empty() {
    let result = ExtractionResult {
        markdown: String::new(),
        text: String::new(),
        page_count: 0,
        pages: vec![],
        source: None,
    };

    assert_eq!(result.page_count, 0);
    assert!(result.pages.is_empty());
    assert!(result.source.is_none());
}

#[test]
fn test_extraction_result_multiple_pages() {
    let result = ExtractionResult {
        markdown: "Page 1\n\nPage 2\n\nPage 3".to_string(),
        text: "Page 1\n\nPage 2\n\nPage 3".to_string(),
        page_count: 3,
        pages: vec![
            PageInfo {
                page_number: 1,
                text: "Page 1".to_string(),
                char_count: 6,
            },
            PageInfo {
                page_number: 2,
                text: "Page 2".to_string(),
                char_count: 6,
            },
            PageInfo {
                page_number: 3,
                text: "Page 3".to_string(),
                char_count: 6,
            },
        ],
        source: Some("/path/to/file.pdf".into()),
    };

    assert_eq!(result.page_count, 3);
    assert_eq!(result.pages.len(), 3);
    assert_eq!(result.pages[2].page_number, 3);
}

#[test]
fn test_config_clone() {
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 200,
            format: ImageFormat::Png,
        },
        page_range: Some(1..=3),
        password: Some("pass".to_string()),
        parallel: true,
    };

    let cloned = config.clone();
    assert_eq!(cloned.parallel, config.parallel);
    assert_eq!(cloned.password, config.password);
}
