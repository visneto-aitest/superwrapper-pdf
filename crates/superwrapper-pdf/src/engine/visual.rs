use crate::engine::PdfEngine;
use crate::error::{Result, SuperWrapperError};
use crate::types::{ExtractionConfig, ExtractionMode, ExtractionResult, ImageFormat, PageInfo};
use image::ImageFormat as ImgFormat;
use pdfium_render::prelude::*;
use std::path::Path;

pub struct VisualEngine;

impl PdfEngine for VisualEngine {
    fn name(&self) -> &'static str {
        "VisualEngine"
    }

    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult> {
        let ExtractionMode::Visual { dpi, format } = &config.mode else {
            return Err(SuperWrapperError::FeatureNotEnabled {
                mode: "Visual".to_string(),
                feature: "visual".to_string(),
            });
        };

        self.render_pages(path, *dpi, format, config)
    }
}

impl VisualEngine {
    fn render_pages(
        &self,
        path: &Path,
        _dpi: u32,
        format: &ImageFormat,
        config: &ExtractionConfig,
    ) -> Result<ExtractionResult> {
        let pdfium = Pdfium::default();
        let document = pdfium
            .load_pdf_from_file(path, config.password.as_deref())
            .map_err(|e| SuperWrapperError::Pdfium(e.to_string()))?;

        let page_count = document.pages().len() as u32;

        let page_range = config
            .page_range
            .clone()
            .unwrap_or(0..=page_count.saturating_sub(1));

        let render_config =
            PdfRenderConfig::new().rotate_if_landscape(PdfPageRenderRotation::Degrees90, true);

        let mut pages = Vec::new();
        let mut all_text = String::new();

        for page_num in page_range {
            let page_index = page_num as u16;
            if page_index as usize >= document.pages().len() as usize {
                return Err(SuperWrapperError::PageOutOfRange {
                    requested: page_num,
                    total: page_count,
                });
            }

            let page = document.pages().get(page_index).unwrap();

            let rendered = page
                .render_with_config(&render_config)
                .map_err(|e| SuperWrapperError::Pdfium(e.to_string()))?;

            let image = rendered.as_image();

            let img_format = match format {
                ImageFormat::Png => ImgFormat::Png,
                ImageFormat::Jpeg(_) => ImgFormat::Jpeg,
            };

            let mut buffer = Vec::new();
            image
                .write_to(&mut std::io::Cursor::new(&mut buffer), img_format)
                .map_err(|e| SuperWrapperError::Pdfium(e.to_string()))?;

            let text = page
                .text()
                .map_err(|e| SuperWrapperError::Pdfium(e.to_string()))?
                .to_string();

            all_text.push_str(&text);
            if page_num < page_count.saturating_sub(1) {
                all_text.push_str("\n\n");
            }

            pages.push(PageInfo {
                page_number: page_num + 1,
                char_count: text.len(),
                text,
            });
        }

        Ok(ExtractionResult {
            markdown: String::new(),
            text: all_text,
            page_count,
            pages,
            source: Some(path.to_path_buf()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::ExtractionConfig;

    #[test]
    fn test_visual_engine_name() {
        let engine = VisualEngine;
        assert_eq!(engine.name(), "VisualEngine");
    }

    #[test]
    fn test_extract_requires_visual_mode() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = VisualEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(&path, &config);

        assert!(result.is_err());
    }

    #[test]
    fn test_extract_with_visual_mode() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
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
    fn test_extract_jpeg_format() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
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
    fn test_page_info() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = VisualEngine;
        let config = ExtractionConfig {
            mode: ExtractionMode::Visual {
                dpi: 150,
                format: ImageFormat::Png,
            },
            ..Default::default()
        };

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.pages.len() > 0);
        let page = &result.pages[0];
        assert!(page.page_number > 0);
    }

    #[test]
    fn test_source_path() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = VisualEngine;
        let config = ExtractionConfig {
            mode: ExtractionMode::Visual {
                dpi: 150,
                format: ImageFormat::Png,
            },
            ..Default::default()
        };

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.source.is_some());
    }
}
