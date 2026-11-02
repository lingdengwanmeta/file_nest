import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite 单例封装。
///
/// 分类树使用邻接表：每一行记录自己的 parent_id，层级不设上限，
/// 删除父节点时通过外键 ON DELETE CASCADE 级联删除整棵子树。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String dbName = 'file_nest.db';
  static const int dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, dbName),
      version: dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_id INTEGER REFERENCES nodes(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            rel_path TEXT,
            size INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_nodes_parent ON nodes(parent_id)');
        await db.execute('CREATE INDEX idx_nodes_name ON nodes(name)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 为初始版本，后续结构变更在此按 oldVersion 递增迁移。
      },
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
