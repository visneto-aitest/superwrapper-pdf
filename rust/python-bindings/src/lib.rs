use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use std::path::PathBuf;

use superwrapper_pdf as swp_pdf;

/// Python wrapper for ExtractionResult
#[pyclass]
pub struct PyExtractionResult {
    pub inner: swp_pdf::ExtractionResult,
}

#[pymethods]
impl PyExtractionResult {
    #[getter]
    fn markdown(&self) -> String {
        self.inner.markdown.clone()
    }

    #[getter]
    fn text(&self) -> String {
        self.inner.text.clone()
    }

    #[getter]
    fn page_count(&self) -> u32 {
        self.inner.page_count
    }

    #[getter]
    fn pages(&self, py: Python) -> PyResult<Py<PyAny>> {
        let pages_list = pyo3::types::PyList::empty(py);
        for page in &self.inner.pages {
            let page_dict = pyo3::types::PyDict::new(py);
            page_dict.set_item("page_number", page.page_number)?;
            page_dict.set_item("text", &page.text)?;
            page_dict.set_item("char_count", page.char_count)?;
            pages_list.append(page_dict)?;
        }
        Ok(pages_list.into_pyobject(py)?.unbind().into())
    }

    #[getter]
    fn source(&self) -> Option<String> {
        self.inner
            .source
            .as_ref()
            .map(|p| p.to_string_lossy().to_string())
    }

    fn __repr__(&self) -> String {
        format!("ExtractionResult(pages={})", self.inner.page_count)
    }
}

/// Python wrapper for ExtractionConfig
#[pyclass]
#[derive(Clone)]
pub struct PyExtractionConfig {
    pub inner: swp_pdf::ExtractionConfig,
}

#[pymethods]
impl PyExtractionConfig {
    #[new]
    #[pyo3(signature = (mode="fast", page_range=None, password=None, parallel=true))]
    fn new(
        mode: Option<&str>,
        page_range: Option<(u32, u32)>,
        password: Option<String>,
        parallel: Option<bool>,
    ) -> PyResult<Self> {
        let mode_inner = match mode.unwrap_or("fast").to_lowercase().as_str() {
            "fast" => swp_pdf::ExtractionMode::Fast,
            "structured" => swp_pdf::ExtractionMode::Structured,
            _ => {
                return Err(PyRuntimeError::new_err(format!(
                    "Unknown mode: {}",
                    mode.unwrap()
                )))
            }
        };

        let page_range_inner = page_range.map(|(s, e)| s..=e);

        let inner = swp_pdf::ExtractionConfig {
            mode: mode_inner,
            page_range: page_range_inner,
            password,
            parallel: parallel.unwrap_or(true),
        };

        let page_range_inner = page_range.map(|(s, e)| s..=e);

        let inner = swp_pdf::ExtractionConfig {
            mode: mode_inner,
            page_range: page_range_inner,
            password,
            parallel: parallel.unwrap_or(true),
        };

        Ok(PyExtractionConfig { inner })
    }

    fn __repr__(&self) -> String {
        format!("ExtractionConfig(mode={:?})", self.inner.mode)
    }
}

/// Extract PDF content using the specified configuration
#[pyfunction]
#[pyo3(signature = (path, config=None))]
fn extract_pdf(path: String, config: Option<PyExtractionConfig>) -> PyResult<PyExtractionResult> {
    let path_buf = PathBuf::from(&path);
    let config_inner = config
        .map(|c| c.inner)
        .unwrap_or_else(|| swp_pdf::ExtractionConfig::default());

    let engine: Box<dyn swp_pdf::PdfEngine> = match config_inner.mode {
        swp_pdf::ExtractionMode::Fast => Box::new(swp_pdf::FastEngine),
        swp_pdf::ExtractionMode::Structured => Box::new(swp_pdf::StructuredEngine),
        _ => return Err(PyRuntimeError::new_err("Visual mode not yet implemented")),
    };

    let result = engine
        .extract(&path_buf, &config_inner)
        .map_err(|e| PyRuntimeError::new_err(format!("Extraction failed: {}", e)))?;

    Ok(PyExtractionResult { inner: result })
}

/// Python module initialization
#[pymodule]
fn _superwrapper_pdf_internal(py: Python, m: &Bound<PyModule>) -> PyResult<()> {
    m.add_class::<PyExtractionResult>()?;
    m.add_class::<PyExtractionConfig>()?;
    m.add_function(wrap_pyfunction!(extract_pdf, py)?)?;
    Ok(())
}
