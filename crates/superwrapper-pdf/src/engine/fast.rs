//! FastEngine implementation using pdf_oxide
//!
//! This engine provides high-speed plain text extraction optimized for raw performance.
//! It's the default choice when speed is the primary concern and structured output
//! is not required.
//!
//! # Performance Characteristics
//!
//! - **Speed**: ⚡⚡⚡ (fastest of all engines)
//! - **Memory**: Low footprint
//! - **Output**: Plain text only
//! - **Dependencies**: None (pdf_oxide is always included)
//!
//! # When to Use FastEngine
//!
//! - Batch processing large numbers of PDFs
//! - Text extraction where format doesn't matter
//! - Resource-constrained environments
//! - When you need the quickest possible extraction

use crate::engine::PdfEngine;
use crate::error::{Result, SuperWrapperError};
use crate::types::{ExtractionConfig, ExtractionResult, PageInfo};
use pdf_oxide::document::PdfDocument;
use std::io::Write;
use std::path::Path;

/// FastEngine - Optimized for speed over all other concerns
///
/// This engine uses pdf_oxide to extract plain text from PDFs with minimal overhead.
/// It's the default engine and has no optional feature requirements.
///
/// # Example
///
/// ```rust,no_run
/// use superwrapper_pdf::{FastEngine, PdfEngine, ExtractionConfig};
/// use std::path::Path;
///
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let engine = FastEngine;
/// let config = ExtractionConfig::default();
/// let result = engine.extract(Path::new("document.pdf"), &config)?;
/// # Ok(())
/// # }
/// ```
pub struct FastEngine;

impl PdfEngine for FastEngine {
    fn name(&self) -> &'static str {
        "FastEngine"
    }

    fn extract(&self, path: &Path, config: &ExtractionConfig) -> Result<ExtractionResult> {
        if config.parallel {
            self.extract_parallel(path)
        } else {
            self.extract_sequential(path, config)
        }
    }
}

impl FastEngine {
    pub fn create_test_pdf() -> tempfile::NamedTempFile {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        let pdf_content = generate_simple_pdf();
        file.write_all(pdf_content.as_bytes()).unwrap();
        file.flush().unwrap();
        file
    }

    pub fn create_multipage_test_pdf() -> tempfile::NamedTempFile {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        let pdf_content = generate_multipage_pdf();
        file.write_all(pdf_content.as_bytes()).unwrap();
        file.flush().unwrap();
        file
    }

    pub fn fixture_pdf(name: &str) -> std::path::PathBuf {
        let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        crate_root.join("tests").join("fixtures").join(name)
    }

    fn extract_sequential(
        &self,
        path: &Path,
        config: &ExtractionConfig,
    ) -> Result<ExtractionResult> {
        let mut doc =
            PdfDocument::open(path).map_err(|e| SuperWrapperError::PdfParse(e.to_string()))?;

        let page_count =
            doc.page_count()
                .map_err(|e| SuperWrapperError::PdfParse(e.to_string()))? as u32;

        let page_range = config
            .page_range
            .clone()
            .unwrap_or(0..=page_count.saturating_sub(1));

        let mut pages = Vec::new();
        let mut all_text = String::new();

        for page_num in page_range {
            let text = doc
                .extract_text(page_num as usize)
                .map_err(|e| SuperWrapperError::PdfParse(e.to_string()))?;
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
            markdown: all_text.clone(),
            text: all_text,
            page_count,
            pages,
            source: Some(path.to_path_buf()),
        })
    }

    fn extract_parallel(&self, path: &Path) -> Result<ExtractionResult> {
        let texts = pdf_oxide::parallel::ParallelExtractor::extract_all_text(path)
            .map_err(|e| SuperWrapperError::PdfParse(e.to_string()))?;

        let page_count = texts.len() as u32;
        let all_text = texts.join("\n\n");

        let pages: Vec<PageInfo> = texts
            .into_iter()
            .enumerate()
            .map(|(i, text)| PageInfo {
                page_number: (i + 1) as u32,
                char_count: text.len(),
                text,
            })
            .collect();

        Ok(ExtractionResult {
            markdown: all_text.clone(),
            text: all_text,
            page_count,
            pages,
            source: Some(path.to_path_buf()),
        })
    }
}

fn generate_simple_pdf() -> String {
    r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> >>
endobj
4 0 obj
<< /Length 44 >>
stream
BT
/F1 12 Tf
100 700 Td
(Test PDF for unit testing) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000266 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
351
%%EOF
"#
    .to_string()
}

fn generate_multipage_pdf() -> String {
    r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R 6 0 R 9 0 R] /Count 3 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> >>
endobj
4 0 obj
<< /Length 47 >>
stream
BT
/F1 12 Tf
100 700 Td
(Page 1 - Hello World) Tj
ET
endstream
endobj
5 0 obj
<< /Type /ObjStm /Length 5 /First 0 >>
endobj
6 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 7 0 R /Resources << >> >>
endobj
7 0 obj
<< /Length 47 >>
stream
BT
/F1 12 Tf
100 700 Td
(Page 2 - Testing PDF) Tj
ET
endstream
endobj
8 0 obj
<< /Type /ObjStm /Length 5 /First 0 >>
endobj
9 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 10 0 R /Resources << >> >>
endobj
10 0 obj
<< /Length 47 >>
stream
BT
/F1 12 Tf
100 700 Td
(Page 3 - Final Page) Tj
ET
endstream
endobj
xref
0 11
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000206 00000 n 
0000000263 00000 n 
0000000314 00000 n 
0000000405 00000 n 
0000000456 00000 n 
0000000507 00000 n 
0000000558 00000 n 
trailer
<< /Size 11 /Root 1 0 R >>
startxref
609
%%EOF
"#
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::ExtractionConfig;

    #[test]
    fn test_fast_engine_name() {
        let engine = FastEngine;
        assert_eq!(engine.name(), "FastEngine");
    }

    #[test]
    fn test_extract_sequential() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.page_count, 1);
    }

    #[test]
    fn test_extract_parallel() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig {
            parallel: true,
            ..Default::default()
        };

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.page_count, 1);
    }

    #[test]
    fn test_page_info() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.pages.len(), 1);
        let page = &result.pages[0];
        assert_eq!(page.page_number, 1);
    }

    #[test]
    fn test_page_range() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig {
            page_range: Some(0..=0),
            ..Default::default()
        };

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.pages.len(), 1);
    }

    #[test]
    fn test_source_path() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        assert!(result.source.is_some());
    }

    #[test]
    fn test_markdown_equals_text() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.markdown, result.text);
    }

    #[test]
    fn test_empty_page_range() {
        let file = FastEngine::create_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig {
            page_range: Some(0..=0),
            ..Default::default()
        };

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.pages.len(), 1);
    }

    #[test]
    fn test_multipage_pdf() {
        let file = FastEngine::create_multipage_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.page_count, 3);
        assert_eq!(result.pages.len(), 3);
    }

    #[test]
    fn test_multipage_parallel() {
        let file = FastEngine::create_multipage_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig {
            parallel: true,
            ..Default::default()
        };

        let result = engine.extract(file.path(), &config).unwrap();

        assert_eq!(result.page_count, 3);
    }

    #[test]
    fn test_all_pages_have_correct_numbers() {
        let file = FastEngine::create_multipage_test_pdf();
        let engine = FastEngine;
        let config = ExtractionConfig::default();

        let result = engine.extract(file.path(), &config).unwrap();

        for (i, page) in result.pages.iter().enumerate() {
            assert_eq!(page.page_number, (i + 1) as u32);
        }
    }
}
