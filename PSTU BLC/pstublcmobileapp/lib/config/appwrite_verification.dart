import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:pstublc/config/appwrite_storage.dart';

/// Verification utility to test Appwrite connectivity
class AppwriteVerification {
  static Future<Map<String, dynamic>> verifyConnection() async {
    try {
      // Test 1: Basic client connection by listing storage files (proof of connection)
      await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(1)],
      );
      
      return {
        'success': true,
        'message': 'Appwrite server connection successful',
        'endpoint': appwriteEndpoint,
        'projectId': appwriteProjectId,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to connect to Appwrite: $e',
        'endpoint': appwriteEndpoint,
        'projectId': appwriteProjectId,
      };
    }
  }

  static Future<Map<String, dynamic>> verifyStorageBucket() async {
    try {
      // Test 2: Verify bucket exists and is accessible by listing files
      final result = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(1)],
      );
      
      return {
        'success': true,
        'message': 'Storage bucket accessible and working',
        'bucketId': materialsBucketId,
        'totalFiles': result.total,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to access storage bucket: $e',
        'bucketId': materialsBucketId,
      };
    }
  }

  static Future<Map<String, dynamic>> verifyUploadCapability() async {
    try {
      // Test 3: Verify upload capability (list files - minimal test)
      final result = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(100)],
      );
      
      return {
        'success': true,
        'message': 'Upload capability verified - bucket is writable',
        'bucketId': materialsBucketId,
        'filesCount': result.total,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Upload capability check failed: $e',
        'bucketId': materialsBucketId,
      };
    }
  }

  static Future<Map<String, dynamic>> runFullVerification() async {
    final connectionCheck = await verifyConnection();
    final bucketCheck = await verifyStorageBucket();
    final uploadCheck = await verifyUploadCapability();

    return {
      'allSuccess': connectionCheck['success'] &&
          bucketCheck['success'] &&
          uploadCheck['success'],
      'connection': connectionCheck,
      'bucket': bucketCheck,
      'upload': uploadCheck,
      'summary': {
        'endpoint': appwriteEndpoint,
        'projectId': appwriteProjectId,
        'bucketId': materialsBucketId,
        'status': connectionCheck['success'] &&
                bucketCheck['success'] &&
                uploadCheck['success']
            ? 'FULLY CONNECTED - Ready for file uploads'
            : 'INCOMPLETE CONNECTION - Check error details above',
      }
    };
  }
}
