//! Caching layer for PDF extraction results
//!
//! This module provides LRU caching with TTL (time-to-live) support for extraction results.
//! When the `async` feature is enabled, this module provides cached extraction capabilities.

use crate::error::Result;
use crate::types::{ExtractionConfig, ExtractionResult};
use lru::LruCache;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Cache entry with TTL tracking
struct CacheEntry {
    result: ExtractionResult,
    created_at: Instant,
    ttl: Duration,
}

impl CacheEntry {
    fn is_expired(&self) -> bool {
        self.created_at.elapsed() > self.ttl
    }
}

/// Cache configuration
#[derive(Clone, Debug)]
pub struct CacheConfig {
    /// Maximum number of entries to cache
    pub max_entries: usize,
    /// Time-to-live for cache entries
    pub ttl: Duration,
    /// Enable TTL eviction (default true)
    pub enable_ttl_eviction: bool,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            max_entries: 100,
            ttl: Duration::from_secs(3600), // 1 hour default
            enable_ttl_eviction: true,
        }
    }
}

impl CacheConfig {
    /// Create a new cache config with custom settings
    pub fn new(max_entries: usize, ttl_secs: u64) -> Self {
        Self {
            max_entries,
            ttl: Duration::from_secs(ttl_secs),
            enable_ttl_eviction: true,
        }
    }
}

/// Cache key based on path and config
#[derive(Clone, Debug, Hash, Eq, PartialEq)]
struct CacheKey {
    path: PathBuf,
    mode: String,
}

impl CacheKey {
    fn new(path: &PathBuf, config: &ExtractionConfig) -> Self {
        Self {
            path: path.clone(),
            mode: format!("{:?}", config.mode),
        }
    }
}

/// Extraction result cache with LRU + TTL
pub struct ExtractionCache {
    cache: RwLock<LruCache<CacheKey, CacheEntry>>,
    config: CacheConfig,
}

impl ExtractionCache {
    /// Create a new extraction cache
    pub fn new(config: CacheConfig) -> Self {
        let cache = LruCache::new(
            std::num::NonZeroUsize::new(config.max_entries).unwrap_or(
                std::num::NonZeroUsize::new(100).unwrap()
            )
        );
        Self {
            cache: RwLock::new(cache),
            config,
        }
    }

    /// Get a cached result if available and not expired
    pub async fn get(&self, path: &PathBuf, config: &ExtractionConfig) -> Option<ExtractionResult> {
        let key = CacheKey::new(path, config);
        let mut cache = self.cache.write().await;
        
        if let Some(entry) = cache.get(&key) {
            if !entry.is_expired() {
                return Some(entry.result.clone());
            }
            cache.pop(&key);
        }
        None
    }

    /// Store a result in the cache
    pub async fn insert(&self, path: &PathBuf, config: &ExtractionConfig, result: ExtractionResult) {
        let key = CacheKey::new(path, config);
        let entry = CacheEntry {
            result,
            created_at: Instant::now(),
            ttl: self.config.ttl,
        };
        
        let mut cache = self.cache.write().await;
        cache.push(key, entry);
    }

    /// Clear all cached entries
    pub async fn clear(&self) {
        let mut cache = self.cache.write().await;
        cache.clear();
    }

    /// Remove expired entries (for manual triggering)
    pub async fn evict_expired(&self) -> usize {
        let mut cache = self.cache.write().await;
        let mut removed = 0;
        
        let keys: Vec<_> = cache.iter()
            .filter(|(_, entry)| entry.is_expired())
            .map(|(k, _)| k.clone())
            .collect();
        
        for key in keys {
            cache.pop(&key);
            removed += 1;
        }
        
        removed
    }

    /// Get current cache size
    pub async fn len(&self) -> usize {
        let cache = self.cache.read().await;
        cache.len()
    }
}

/// Cached extraction wrapper
///
/// Wraps an engine and provides caching on top of extraction operations.
#[derive(Clone)]
pub struct CachedEngine<E> {
    engine: Arc<E>,
    cache: Arc<ExtractionCache>,
}

impl<E> CachedEngine<E> {
    /// Create a new cached engine wrapper
    pub fn new(engine: E, config: CacheConfig) -> Self {
        Self {
            engine: Arc::new(engine),
            cache: Arc::new(ExtractionCache::new(config)),
        }
    }

    /// Get the underlying engine
    pub fn engine(&self) -> &Arc<E> {
        &self.engine
    }

    /// Get the cache
    pub fn cache(&self) -> &Arc<ExtractionCache> {
        &self.cache
    }

    /// Extract with caching
    pub async fn extract(
        &self,
        path: &PathBuf,
        config: &ExtractionConfig,
    ) -> Result<ExtractionResult>
    where
        E: crate::engine::PdfEngine,
    {
        // Check cache first
        if let Some(result) = self.cache.get(path, config).await {
            return Ok(result);
        }

        // Extract from engine (blocking)
        let result = crate::engine::PdfEngine::extract(self.engine.as_ref(), path, config)?;
        
        // Store in cache
        self.cache.insert(path, config, result.clone()).await;
        
        Ok(result)
    }

    /// Clear the cache
    pub async fn clear_cache(&self) {
        self.cache.clear().await;
    }
}

/// Builder for creating cached engines
pub struct CachedEngineBuilder<E> {
    engine: E,
    cache_config: CacheConfig,
}

impl<E> CachedEngineBuilder<E> {
    /// Create a new builder
    pub fn new(engine: E) -> Self {
        Self {
            engine,
            cache_config: CacheConfig::default(),
        }
    }

    /// Set max cache entries
    pub fn max_entries(mut self, entries: usize) -> Self {
        self.cache_config.max_entries = entries;
        self
    }

    /// Set TTL duration
    pub fn ttl(mut self, ttl: Duration) -> Self {
        self.cache_config.ttl = ttl;
        self
    }

    /// Set TTL in seconds
    pub fn ttl_secs(self, seconds: u64) -> Self {
        self.ttl(Duration::from_secs(seconds))
    }

    /// Build the cached engine
    pub fn build(self) -> CachedEngine<E> {
        CachedEngine::new(self.engine, self.cache_config)
    }
}