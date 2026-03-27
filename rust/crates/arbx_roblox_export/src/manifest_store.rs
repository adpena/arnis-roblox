use std::collections::HashMap;
use std::fs;
use std::path::Path;

use arbx_geo::{BoundingBox, Vec3};
use rusqlite::{params, Connection, OptionalExtension};

use crate::manifest::ChunkManifest;
use crate::subplans::ChunkRef;

pub type ManifestStoreResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Debug, Clone, PartialEq)]
pub struct StoredManifestMeta {
    pub schema_version: String,
    pub world_name: String,
    pub generator: String,
    pub source: String,
    pub meters_per_stud: f64,
    pub chunk_size_studs: i32,
    pub bbox: BoundingBox,
    pub total_features: usize,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StoredChunkRecord {
    pub chunk_id: String,
    pub origin_studs: Vec3,
    pub feature_count: usize,
    pub streaming_cost: f64,
    pub partition_version: String,
    pub subplans_json: String,
    pub chunk_json: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StoredManifestSubset {
    pub meta: StoredManifestMeta,
    pub chunks: Vec<StoredChunkRecord>,
}

fn read_manifest_meta(
    connection: &Connection,
    path: &Path,
) -> ManifestStoreResult<StoredManifestMeta> {
    connection
        .query_row(
            "
            SELECT
                schema_version,
                world_name,
                generator,
                source,
                meters_per_stud,
                chunk_size_studs,
                bbox_min_lat,
                bbox_min_lon,
                bbox_max_lat,
                bbox_max_lon,
                total_features,
                notes_json
            FROM manifest_meta
            WHERE singleton_id = 1
            ",
            [],
            |row| {
                let notes_json: String = row.get(11)?;
                let notes = serde_json::from_str::<Vec<String>>(&notes_json).map_err(|err| {
                    rusqlite::Error::FromSqlConversionFailure(
                        11,
                        rusqlite::types::Type::Text,
                        Box::new(err),
                    )
                })?;

                Ok(StoredManifestMeta {
                    schema_version: row.get(0)?,
                    world_name: row.get(1)?,
                    generator: row.get(2)?,
                    source: row.get(3)?,
                    meters_per_stud: row.get(4)?,
                    chunk_size_studs: row.get(5)?,
                    bbox: BoundingBox::new(row.get(6)?, row.get(7)?, row.get(8)?, row.get(9)?),
                    total_features: row.get::<_, i64>(10)? as usize,
                    notes,
                })
            },
        )
        .optional()?
        .ok_or_else(|| {
            format!(
                "manifest store {} is missing manifest_meta row",
                path.display()
            )
            .into()
        })
}

pub fn write_manifest_sqlite(manifest: &ChunkManifest, path: &Path) -> ManifestStoreResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let mut connection = Connection::open(path)?;
    connection.execute_batch(
        "
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS manifest_meta (
            singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
            schema_version TEXT NOT NULL,
            world_name TEXT NOT NULL,
            generator TEXT NOT NULL,
            source TEXT NOT NULL,
            meters_per_stud REAL NOT NULL,
            chunk_size_studs INTEGER NOT NULL,
            bbox_min_lat REAL NOT NULL,
            bbox_min_lon REAL NOT NULL,
            bbox_max_lat REAL NOT NULL,
            bbox_max_lon REAL NOT NULL,
            total_features INTEGER NOT NULL,
            notes_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS manifest_chunks (
            chunk_id TEXT PRIMARY KEY,
            origin_x REAL NOT NULL,
            origin_y REAL NOT NULL,
            origin_z REAL NOT NULL,
            feature_count INTEGER NOT NULL,
            streaming_cost REAL NOT NULL,
            partition_version TEXT NOT NULL,
            subplans_json TEXT NOT NULL,
            chunk_json TEXT NOT NULL
        );
        ",
    )?;

    let transaction = connection.transaction()?;
    transaction.execute("DELETE FROM manifest_meta", [])?;
    transaction.execute("DELETE FROM manifest_chunks", [])?;

    let notes_json = serde_json::to_string(&manifest.meta.notes)?;
    transaction.execute(
        "
        INSERT INTO manifest_meta (
            singleton_id,
            schema_version,
            world_name,
            generator,
            source,
            meters_per_stud,
            chunk_size_studs,
            bbox_min_lat,
            bbox_min_lon,
            bbox_max_lat,
            bbox_max_lon,
            total_features,
            notes_json
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
        ",
        params![
            1_i64,
            manifest.schema_version,
            manifest.meta.world_name,
            manifest.meta.generator,
            manifest.meta.source,
            manifest.meta.meters_per_stud,
            manifest.meta.chunk_size_studs,
            manifest.meta.bbox.min.lat,
            manifest.meta.bbox.min.lon,
            manifest.meta.bbox.max.lat,
            manifest.meta.bbox.max.lon,
            manifest.meta.total_features as i64,
            notes_json,
        ],
    )?;

    let chunk_refs_by_id: HashMap<&str, &ChunkRef> = manifest
        .chunk_refs
        .iter()
        .map(|chunk_ref| (chunk_ref.id.as_str(), chunk_ref))
        .collect();

    let mut statement = transaction.prepare(
        "
        INSERT INTO manifest_chunks (
            chunk_id,
            origin_x,
            origin_y,
            origin_z,
            feature_count,
            streaming_cost,
            partition_version,
            subplans_json,
            chunk_json
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        ",
    )?;

    for chunk in &manifest.chunks {
        let chunk_id = chunk.id.label();
        let chunk_ref = chunk_refs_by_id
            .get(chunk_id.as_str())
            .ok_or_else(|| format!("missing chunkRef for chunk {}", chunk_id))?;
        let subplans_json = serde_json::to_string(&chunk_ref.subplans)?;

        statement.execute(params![
            chunk_id,
            chunk.origin_studs.x,
            chunk.origin_studs.y,
            chunk.origin_studs.z,
            chunk_ref.feature_count as i64,
            chunk_ref.streaming_cost,
            chunk_ref.partition_version,
            subplans_json,
            chunk.to_json_pretty(),
        ])?;
    }

    drop(statement);
    transaction.commit()?;
    Ok(())
}

pub fn read_manifest_sqlite_subset(
    path: &Path,
    chunk_ids: &[String],
) -> ManifestStoreResult<StoredManifestSubset> {
    let connection = Connection::open(path)?;
    let meta = read_manifest_meta(&connection, path)?;

    let mut statement = connection.prepare(
        "
        SELECT
            chunk_id,
            origin_x,
            origin_y,
            origin_z,
            feature_count,
            streaming_cost,
            partition_version,
            subplans_json,
            chunk_json
        FROM manifest_chunks
        WHERE chunk_id = ?1
        ",
    )?;

    let mut chunks = Vec::with_capacity(chunk_ids.len());
    for chunk_id in chunk_ids {
        let chunk = statement
            .query_row(params![chunk_id], |row| {
                Ok(StoredChunkRecord {
                    chunk_id: row.get(0)?,
                    origin_studs: Vec3::new(row.get(1)?, row.get(2)?, row.get(3)?),
                    feature_count: row.get::<_, i64>(4)? as usize,
                    streaming_cost: row.get(5)?,
                    partition_version: row.get(6)?,
                    subplans_json: row.get(7)?,
                    chunk_json: row.get(8)?,
                })
            })
            .optional()?
            .ok_or_else(|| {
                format!(
                    "manifest store {} is missing chunk {}",
                    path.display(),
                    chunk_id
                )
            })?;
        chunks.push(chunk);
    }

    Ok(StoredManifestSubset { meta, chunks })
}

pub fn read_manifest_sqlite_all(path: &Path) -> ManifestStoreResult<StoredManifestSubset> {
    let connection = Connection::open(path)?;
    let meta = read_manifest_meta(&connection, path)?;
    let mut statement = connection.prepare(
        "
        SELECT
            chunk_id,
            origin_x,
            origin_y,
            origin_z,
            feature_count,
            streaming_cost,
            partition_version,
            subplans_json,
            chunk_json
        FROM manifest_chunks
        ORDER BY chunk_id ASC
        ",
    )?;
    let chunks = statement
        .query_map([], |row| {
            Ok(StoredChunkRecord {
                chunk_id: row.get(0)?,
                origin_studs: Vec3::new(row.get(1)?, row.get(2)?, row.get(3)?),
                feature_count: row.get::<_, i64>(4)? as usize,
                streaming_cost: row.get(5)?,
                partition_version: row.get(6)?,
                subplans_json: row.get(7)?,
                chunk_json: row.get(8)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(StoredManifestSubset { meta, chunks })
}
