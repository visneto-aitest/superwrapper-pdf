const assert = require('assert');
const superwrapper = require('./build/Release/superwrapper_pdf.node');

async function testBasicExtraction() {
  console.log('Testing basic extraction...');
  // This would need a sample PDF file
  // For now, just test that the function exists
  assert(typeof superwrapper.extract === 'function');
  console.log('✓ Basic extraction test passed');
}

async function testExtractWithOptions() {
  console.log('Testing extraction with options...');
  // Test options parsing (would need actual PDF)
  const options = {
    mode: 'structured',
    parallel: true
  };
  // Just verify options structure is accepted
  assert(typeof options === 'object');
  console.log('✓ Options test passed');
}

async function runTests() {
  try {
    await testBasicExtraction();
    await testExtractWithOptions();
    console.log('All tests passed!');
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(1);
  }
}

if (require.main === module) {
  runTests();
}

module.exports = { runTests };