import 'package:flutter/material.dart';
import 'package:pstublc/config/appwrite_verification.dart';

class AppwriteDebugScreen extends StatefulWidget {
  const AppwriteDebugScreen({super.key});

  @override
  State<AppwriteDebugScreen> createState() => _AppwriteDebugScreenState();
}

class _AppwriteDebugScreenState extends State<AppwriteDebugScreen> {
  Map<String, dynamic>? _verificationResult;
  bool _isLoading = false;

  Future<void> _runVerification() async {
    setState(() => _isLoading = true);
    final result = await AppwriteVerification.runFullVerification();
    setState(() {
      _verificationResult = result;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _runVerification();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appwrite Connection Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _verificationResult == null
                ? const Center(child: Text('No verification data'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overall Status
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: (_verificationResult!['allSuccess'] ?? false)
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          border: Border.all(
                            color: (_verificationResult!['allSuccess'] ?? false)
                                ? Colors.green
                                : Colors.red,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _verificationResult!['summary']['status'] ?? '',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: (_verificationResult!['allSuccess'] ??
                                        false)
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Summary Section
                      const Text(
                        'Configuration Summary:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryItem(
                        'Endpoint',
                        _verificationResult!['summary']['endpoint'] ?? 'N/A',
                      ),
                      _buildSummaryItem(
                        'Project ID',
                        _verificationResult!['summary']['projectId'] ?? 'N/A',
                      ),
                      _buildSummaryItem(
                        'Bucket ID',
                        _verificationResult!['summary']['bucketId'] ?? 'N/A',
                      ),
                      const SizedBox(height: 20),

                      // Connection Test
                      _buildTestResultCard(
                        title: 'Server Connection Test',
                        result: _verificationResult!['connection'],
                      ),
                      const SizedBox(height: 12),

                      // Bucket Test
                      _buildTestResultCard(
                        title: 'Storage Bucket Test',
                        result: _verificationResult!['bucket'],
                      ),
                      const SizedBox(height: 12),

                      // Upload Capability Test
                      _buildTestResultCard(
                        title: 'Upload Capability Test',
                        result: _verificationResult!['upload'],
                      ),
                      const SizedBox(height: 20),

                      // Retry Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _runVerification,
                          child: const Text('Retry Verification'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResultCard({
    required String title,
    required Map<String, dynamic> result,
  }) {
    final success = result['success'] ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05),
        border: Border.all(
          color: success ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: success ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: success ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result['message'] ?? 'No message',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
