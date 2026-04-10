use crate::engine::PdfEngine;
use crate::error::{Result, SuperWrapperError};
use crate::types::{ExtractionConfig, ExtractionResult, PageInfo};
use std::path::Path;
use unpdf::render::RenderOptions;

pub struct StructuredEngine;

impl PdfEngine for StructuredEngine {
    fn name(&self) -> &'static str {
        "StructuredEngine"
    }

    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult> {
        if config.parallel {
            self.extract_parallel(path)
        } else {
            self.extract_sequential(path, config)
        }
    }
}

impl StructuredEngine {
    fn extract_sequential(
        &self,
        path: &Path,
        config: &ExtractionConfig,
    ) -> Result<ExtractionResult> {
        let doc = unpdf::parse_file(path).map_err(|e| SuperWrapperError::Unpdf(e))?;

        let page_count = doc.page_count();
        let page_range = config
            .page_range
            .clone()
            .unwrap_or(0..=page_count.saturating_sub(1));

        let render_options = RenderOptions::default();

        let mut pages = Vec::new();
        let mut all_markdown = String::new();
        let mut all_text = String::new();

        for page_num in page_range {
            let page_index = page_num as u32;
            if page_index >= page_count {
                return Err(SuperWrapperError::PageOutOfRange {
                    requested: page_num,
                    total: page_count,
                    path: Some(path.to_string_lossy().to_string()),
                });
            }

            let page_markdown = unpdf::render::to_markdown(&doc, &render_options)
                .map_err(|e| SuperWrapperError::Unpdf(e))?;

            let page_text = unpdf::render::to_text(&doc, &render_options)
                .map_err(|e| SuperWrapperError::Unpdf(e))?;

            all_markdown.push_str(&page_markdown);
            if page_num < page_count.saturating_sub(1) {
                all_markdown.push_str("\n\n");
            }

            all_text.push_str(&page_text);
            if page_num < page_count.saturating_sub(1) {
                all_text.push_str("\n\n");
            }

            pages.push(PageInfo {
                page_number: page_num + 1,
                char_count: page_text.len(),
                text: page_text,
            });
        }

        Ok(ExtractionResult {
            markdown: all_markdown,
            text: all_text,
            page_count,
            pages,
            source: Some(path.to_path_buf()),
        })
    }

    fn extract_parallel(&self, path: &Path) -> Result<ExtractionResult> {
        let doc = unpdf::parse_file(path).map_err(|e| SuperWrapperError::Unpdf(e))?;

        let page_count = doc.page_count();
        let render_options = RenderOptions::default();

        let full_markdown = unpdf::render::to_markdown(&doc, &render_options)
            .map_err(|e| SuperWrapperError::Unpdf(e))?;

        let full_text = unpdf::render::to_text(&doc, &render_options)
            .map_err(|e| SuperWrapperError::Unpdf(e))?;

        let pages: Vec<PageInfo> = (0..page_count)
            .map(|i| {
                let page_text = unpdf::render::to_text(&doc, &render_options)
                    .map_err(|e| SuperWrapperError::Unpdf(e))
                    .unwrap_or_default();

                PageInfo {
                    page_number: i + 1,
                    char_count: page_text.len(),
                    text: page_text,
                }
            })
            .collect();

        Ok(ExtractionResult {
            markdown: full_markdown,
            text: full_text,
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
    fn test_structured_engine_name() {
        let engine = StructuredEngine;
        assert_eq!(engine.name(), "StructuredEngine");
    }

    #[test]
    fn test_extract_sequential() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = StructuredEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.page_count > 0);
        assert!(!result.text.is_empty());
    }

    #[test]
    fn test_extract_parallel() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = StructuredEngine;
        let config = ExtractionConfig {
            parallel: true,
            ..Default::default()
        };

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.page_count > 0);
    }

    #[test]
    fn test_markdown_output() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = StructuredEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(&path, &config).unwrap();

        assert!(!result.markdown.is_empty());
    }

    #[test]
    fn test_page_info() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = StructuredEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.pages.len() > 0);
        let page = &result.pages[0];
        assert!(page.page_number > 0);
    }

    #[test]
    fn test_source_path() {
        let path = super::super::fast::FastEngine::fixture_pdf("sample.pdf");
        let engine = StructuredEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(&path, &config).unwrap();

        assert!(result.source.is_some());
    }
}
