use criterion::{black_box, criterion_group, criterion_main, Bencher, Criterion};
use std::path::Path;
use superwrapper_pdf::{
    ExtractionConfig, ExtractionMode, FastEngine, ImageFormat, PdfEngine, StructuredEngine,
    VisualEngine,
};

fn bench_fast_engine(c: &mut Criterion) {
    let engine = FastEngine;
    let config = ExtractionConfig::default();
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("fast_engine_extract", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

fn bench_structured_engine(c: &mut Criterion) {
    let engine = StructuredEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        parallel: false,
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("structured_engine_extract", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

fn bench_structured_engine_parallel(c: &mut Criterion) {
    let engine = StructuredEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Structured,
        parallel: true,
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("structured_engine_extract_parallel", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

fn bench_visual_engine_png(c: &mut Criterion) {
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("visual_engine_extract_png", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

fn bench_visual_engine_jpeg(c: &mut Criterion) {
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 150,
            format: ImageFormat::Jpeg(80),
        },
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("visual_engine_extract_jpeg", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

criterion_group!(
    benches,
    bench_fast_engine,
    bench_structured_engine,
    bench_structured_engine_parallel,
    bench_visual_engine_png,
    bench_visual_engine_jpeg
);

criterion_main!(benches);
