#!/usr/bin/env python3
"""Test script for superwrapper-pdf Python bindings."""

import sys
import os

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "crates",
        "superwrapper-pdf",
        "tests",
        "fixtures",
    ),
)

try:
    import _superwrapper_pdf

    print("✓ Successfully imported superwrapper-pdf Python bindings")
    swp = _superwrapper_pdf
except ImportError as e:
    print(f"✗ Failed to import bindings: {e}")
    sys.exit(1)


def test_basic_extraction():
    """Test basic PDF extraction."""
    print("\n--- Testing Basic Extraction ---")

    # Test with simple.pdf
    pdf_path = "../../crates/superwrapper-pdf/tests/fixtures/simple.pdf"
    if not os.path.exists(pdf_path):
        print(f"✗ PDF file not found: {pdf_path}")
        return

    try:
        result = swp.extract_pdf(pdf_path)
        print("✓ Basic extraction successful")
        print(f"  Pages: {result.page_count}")
        print(f"  Text length: {len(result.text)}")
        print(f"  Markdown length: {len(result.markdown)}")
        print(f"  Text preview: {result.text[:100]}...")
        print(f"  Markdown preview: {result.markdown[:100]}...")

        # Test pages
        print(f"  Number of page objects: {len(result.pages)}")
        if result.pages:
            page = result.pages[0]
            print(f"  First page: #{page.page_number}, {page.char_count} chars")
            print(f"  Page text preview: {page.text[:50]}...")

    except Exception as e:
        print(f"✗ Basic extraction failed: {e}")
        return False

    return True


def test_config_extraction():
    """Test extraction with configuration."""
    print("\n--- Testing Config Extraction ---")

    pdf_path = "../../crates/superwrapper-pdf/tests/fixtures/sample.pdf"
    if not os.path.exists(pdf_path):
        print(f"✗ PDF file not found: {pdf_path}")
        return

    try:
        # Test with structured mode
        config = swp.PyExtractionConfig("structured")
        result = swp.extract_pdf(pdf_path, config)
        print("✓ Structured mode extraction successful")
        print(f"  Pages: {result.page_count}")
        print(f"  Text length: {len(result.text)}")
        print(f"  Markdown length: {len(result.markdown)}")

    except Exception as e:
        print(f"✗ Config extraction failed: {e}")
        return False

    return True


def test_error_handling():
    """Test error handling."""
    print("\n--- Testing Error Handling ---")

    try:
        # Test with non-existent file
        result = swp.extract_pdf("nonexistent.pdf")
        print("✗ Should have failed with non-existent file")
        return False
    except Exception as e:
        print(f"✓ Correctly handled error for non-existent file: {type(e).__name__}")

    return True


def main():
    """Run all tests."""
    print("Testing superwrapper-pdf Python bindings")
    print("=" * 50)

    # Change to the script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    tests = [
        test_basic_extraction,
        test_config_extraction,
        test_error_handling,
    ]

    passed = 0
    total = len(tests)

    for test in tests:
        if test():
            passed += 1

    print(f"\n{'=' * 50}")
    print(f"Results: {passed}/{total} tests passed")

    if passed == total:
        print("🎉 All tests passed!")
        return 0
    else:
        print("❌ Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
