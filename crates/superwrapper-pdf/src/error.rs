use thiserror::Error;

#[derive(Error, Debug)]
pub enum SuperWrapperError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("PDF parsing error: {0}")]
    PdfParse(String),

    #[error("Encrypted PDF (no password provided or invalid)")]
    Encrypted,

    #[error("Page {requested} out of range (total: {total})")]
    PageOutOfRange { requested: u32, total: u32 },

    #[error(
        "Extraction mode '{mode}' is not enabled. Build with feature '{feature}' to enable it."
    )]
    FeatureNotEnabled { mode: String, feature: String },

    #[error("pdf_oxide error: {0}")]
    Oxide(#[from] pdf_oxide::Error),

    #[cfg(feature = "structured")]
    #[error("unpdf error: {0}")]
    Unpdf(#[from] unpdf::Error),

    #[cfg(feature = "visual")]
    #[error("pdfium-render error: {0}")]
    Pdfium(String),
}

pub type Result<T> = std::result::Result<T, SuperWrapperError>;
