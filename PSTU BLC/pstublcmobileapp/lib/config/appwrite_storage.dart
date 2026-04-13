import 'package:dart_appwrite/dart_appwrite.dart';

const String appwriteProjectId = '69da1954001b16498918';
const String appwriteEndpoint = 'https://nyc.cloud.appwrite.io/v1';
const String materialsBucketId = '69da22a6000cca44118c';

final Client appwriteClient = Client()
  .setProject(appwriteProjectId)
  .setEndpoint(appwriteEndpoint);

final Storage appwriteStorage = Storage(appwriteClient);
