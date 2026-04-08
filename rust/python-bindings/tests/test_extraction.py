import pytest
from superwrapper_pdf import (
    extract_pdf,
    ExtractionConfig,
    ExtractionMode,
    PyExtractionResult,
)


def test_extract_pdf_basic():
    """Test basic PDF extraction functionality."""
    # This would need a sample PDF file
    # For now, just test that the function exists and has correct signature
    assert callable(extract_pdf)


def test_extraction_config():
    """Test ExtractionConfig creation."""
    config = ExtractionConfig()
    assert config is not None

    config_structured = ExtractionConfig(mode="structured")
    assert config_structured is not None


def test_extraction_mode():
    """Test ExtractionMode constants."""
    mode = ExtractionMode()
    assert hasattr(mode, "FAST")
    assert hasattr(mode, "STRUCTURED")


def test_py_classes():
    """Test that Python classes are properly exposed."""
    # These would be instantiated with actual data in real tests
    assert PyExtractionResult is not None
