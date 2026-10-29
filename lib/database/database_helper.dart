
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance =
  DatabaseHelper._();

  Database? _database;

  Future<Database> get database async {
    return _database ??= await _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final dbPath = join(
      await getDatabasesPath(),
      'task_manager.db',
    );

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> registerUser({
    required String fullName,
    required String email,
    required String passwordHash,
  }) async {
    final db = await database;

    return db.insert(
      'users',
      {
        'full_name': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password_hash': passwordHash,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
