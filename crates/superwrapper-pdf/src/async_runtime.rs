//! Async runtime support for PDF extraction
//!
//! This module provides async/await support for PDF extraction operations using Tokio.
//! When the `async` feature is enabled, engines can perform extraction in non-blocking fashion.

use crate::error::{Result, SuperWrapperError};
use crate::types::{ExtractionConfig, ExtractionResult};
use futures;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::task;

/// Async-compatible engine wrapper
///
/// Engines are wrapped in Arc to allow safe sharing across async tasks.
pub type AsyncEngine<E> = Arc<E>;

/// Execute blocking extraction in a separate thread
///
/// This helper allows synchronous extraction operations to be executed
/// in a tokio runtime without blocking the async executor.
#[cfg(feature = "async")]
pub async fn extract_in_task<E>(
    engine: AsyncEngine<E>,
    path: &PathBuf,
    config: &ExtractionConfig,
) -> Result<ExtractionResult>
where
    E: crate::engine::PdfEngine + Send + Sync + 'static,
{
    let path = path.clone();
    let config = config.clone();

    task::spawn_blocking(move || {
        let engine = engine.as_ref();
        engine.extract(&path, &config)
    })
    .await
    .map_err(|e| SuperWrapperError::PdfParse {
        path: None,
        details: format!("Task join error: {}", e),
    })?
}

/// Extract multiple PDFs concurrently
///
/// This function processes multiple PDF files in parallel using Tokio's
/// async runtime. Each extraction runs in a separate blocking thread.
#[cfg(feature = "async")]
pub async fn extract_batch<E>(
    engine: AsyncEngine<E>,
    paths: &[PathBuf],
    config: &ExtractionConfig,
) -> Vec<Result<ExtractionResult>>
where
    E: crate::engine::PdfEngine + Send + Sync + 'static,
{
    let futures: Vec<_> = paths
        .iter()
        .map(|path| extract_in_task(engine.clone(), path, config))
        .collect();

    futures::future::join_all(futures).await
}