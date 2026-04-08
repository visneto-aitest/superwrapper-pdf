# superwrapper-pdf Node.js Bindings

Node.js bindings for the `superwrapper-pdf` Rust library, providing fast PDF text and markdown extraction using N-API.

## Installation

### From Source

```bash
# Install dependencies
npm install

# Build the native addon
npm run build
```

### Development

```bash
# Build with debug symbols
npm run build-debug

# Clean build artifacts
npm run clean
```

## Usage

```javascript
const superwrapper = require('superwrapper-pdf');

async function extractPDF() {
  try {
    // Simple extraction
    const result = await superwrapper.extract('document.pdf');
    console.log(`Pages: ${result.pageCount}`);
    console.log(`Text: ${result.text.substring(0, 200)}...`);

    // With options
    const result2 = await superwrapper.extract('document.pdf', {
      mode: 'structured',    // 'fast', 'structured', or 'visual'
      pageRange: [0, 2],     // pages 1-3 (0-indexed inclusive)
      parallel: true,        // enable parallel processing
      password: undefined    // for encrypted PDFs
    });

    console.log(`Markdown: ${result2.markdown.substring(0, 200)}...`);

    // Access page details
    result2.pages.forEach(page => {
      console.log(`Page ${page.pageNumber}: ${page.charCount} chars`);
    });

  } catch (error) {
    console.error('Extraction failed:', error);
  }
}

extractPDF();
```

## API Reference

### Functions

#### `extract(path: string, options?: ExtractionOptions): Promise<ExtractionResult>`

Extracts content from a PDF file.

**Parameters:**
- `path: string` - Path to the PDF file
- `options?: ExtractionOptions` - Optional extraction configuration

**Returns:** `Promise<ExtractionResult>` - Extraction result

### Types

#### `ExtractionResult`
```typescript
interface ExtractionResult {
  text: string;           // Plain text content
  markdown: string;       // Extracted markdown content (if available)
  pageCount: number;      // Total number of pages
  pages: PageInfo[];      // Per-page metadata
  source?: string;        // Source file path
}
```

#### `PageInfo`
```typescript
interface PageInfo {
  pageNumber: number;     // 1-indexed page number
  text: string;           // Page text content
  charCount: number;      // Character count
}
```

#### `ExtractionOptions`
```typescript
interface ExtractionOptions {
  mode?: 'fast' | 'structured' | 'visual';  // Extraction mode
  pageRange?: [number, number];             // Page range (0-indexed inclusive)
  password?: string;                        // Password for encrypted PDFs
  parallel?: boolean;                       // Enable parallel processing
}
```

## Requirements

- Node.js 14+
- Rust 1.70+

## Features

- **Fast Mode**: Quick text extraction using pdf_oxide
- **Structured Mode**: Markdown/table extraction using unpdf
- **Page Selection**: Extract specific page ranges
- **Parallel Processing**: Multi-threaded extraction for large PDFs
- **Promise-based**: Modern async/await support
- **N-API**: ABI-stable native addon interface

## Building for Distribution

### Prebuilt Binaries

For distribution, you'll want to build platform-specific binaries:

```bash
# macOS x64
npm run build
# Copy build/Release/superwrapper_pdf.node to platform-specific folder

# Windows x64
# Cross-compile or build on Windows
npm run build

# Linux x64
# Cross-compile or build on Linux
npm run build
```

### CI/CD

Consider using GitHub Actions with matrix builds for multiple platforms.

## Troubleshooting

### Build Issues

- Ensure Rust 1.70+ is installed
- On macOS, install Xcode command line tools: `xcode-select --install`
- On Windows, install Visual Studio Build Tools
- On Linux, install build essentials: `apt-get install build-essential`

### Runtime Issues

- Ensure the PDF file exists and is readable
- For encrypted PDFs, provide the correct password
- Check that the selected mode is supported (structured requires unpdf)

## License

MIT License - see LICENSE file in the root directory.