
import 'package:dotenv/dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart';

Future<Db> connectDatabase() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();

  final uri = env['MONGODB_URI'];

  if (uri == null || uri.isEmpty) {
    throw Exception('MONGODB_URI is missing from .env');
  }

  final db = await Db.create(uri);
  await db.open();

  print('MongoDB connected successfully!');
  print('Connected database: ${db.databaseName}');

  return db;
}
