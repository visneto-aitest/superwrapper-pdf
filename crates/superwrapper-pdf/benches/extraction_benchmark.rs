use criterion::{black_box, criterion_group, criterion_main, Bencher, Criterion};
use std::path::Path;
use std::sync::Arc;
use superwrapper_pdf::{
    ExtractionConfig, ExtractionMode, ExtractionProgress, FastEngine, PdfEngine, StructuredEngine,
};

#[cfg(feature = "visual")]
use superwrapper_pdf::{ImageFormat, VisualEngine};

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

fn bench_fast_engine_parallel(c: &mut Criterion) {
    let engine = FastEngine;
    let config = ExtractionConfig {
        parallel: true,
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("fast_engine_extract_parallel", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

fn bench_fast_engine_streaming(c: &mut Criterion) {
    let engine = FastEngine;
    let config = ExtractionConfig {
        streaming: true,
        chunk_size: Some(10),
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("fast_engine_extract_streaming", |b: &mut Bencher| {
        b.iter(|| {
            let mut count = 0;
            let chunks = engine
                .extract_streaming(black_box(path), black_box(&config))
                .unwrap();
            for chunk in chunks {
                if let Ok(c) = chunk {
                    count += c.pages.len();
                }
            }
            black_box(count);
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

fn bench_progress_callback(c: &mut Criterion) {
    let engine = FastEngine;
    let progress_count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let progress_count_clone = progress_count.clone();

    let callback = Arc::new(move |_progress: &ExtractionProgress| {
        progress_count_clone.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    });

    let config = ExtractionConfig {
        progress_callback: Some(callback),
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("fast_engine_with_progress_callback", |b: &mut Bencher| {
        b.iter(|| {
            progress_count.store(0, std::sync::atomic::Ordering::Relaxed);
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
            black_box(progress_count.load(std::sync::atomic::Ordering::Relaxed));
        })
    });
}

fn bench_page_range(c: &mut Criterion) {
    let engine = FastEngine;
    let config = ExtractionConfig {
        page_range: Some(0..=0),
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("fast_engine_single_page", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

#[cfg(feature = "visual")]
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

#[cfg(feature = "visual")]
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

#[cfg(feature = "visual")]
fn bench_visual_engine_dpi_72(c: &mut Criterion) {
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 72,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("visual_engine_extract_72dpi", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

#[cfg(feature = "visual")]
fn bench_visual_engine_dpi_300(c: &mut Criterion) {
    let engine = VisualEngine;
    let config = ExtractionConfig {
        mode: ExtractionMode::Visual {
            dpi: 300,
            format: ImageFormat::Png,
        },
        ..Default::default()
    };
    let path = Path::new("tests/fixtures/sample.pdf");

    c.bench_function("visual_engine_extract_300dpi", |b: &mut Bencher| {
        b.iter(|| {
            let _result = engine.extract(black_box(path), black_box(&config)).unwrap();
        })
    });
}

#[cfg(not(feature = "visual"))]
criterion_group!(
    benches,
    bench_fast_engine,
    bench_fast_engine_parallel,
    bench_fast_engine_streaming,
    bench_structured_engine,
    bench_structured_engine_parallel,
    bench_progress_callback,
    bench_page_range
);

#[cfg(feature = "visual")]
criterion_group!(
    benches,
    bench_fast_engine,
    bench_fast_engine_parallel,
    bench_fast_engine_streaming,
    bench_structured_engine,
    bench_structured_engine_parallel,
    bench_progress_callback,
    bench_page_range,
    bench_visual_engine_png,
    bench_visual_engine_jpeg,
    bench_visual_engine_dpi_72,
    bench_visual_engine_dpi_300
);

criterion_main!(benches);
