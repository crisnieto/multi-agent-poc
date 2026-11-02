import Database from 'better-sqlite3';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { mkdirSync } from 'node:fs';

export function openDb(): Database.Database {
  const path = process.env.POC_DB_PATH ?? resolve(process.cwd(), 'poc.sqlite');
  mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(readFileSync(resolve(import.meta.dirname, 'schema.sql'), 'utf8'));
  return db;
}
