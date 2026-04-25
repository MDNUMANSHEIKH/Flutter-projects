import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:dio/dio.dart';
import 'package:pstublc/splash_screen.dart';
import 'package:pstublc/services/api_service.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PSTU BLC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: ApiService.noInternetNotifier,
          builder: (context, hasNoInternet, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: ApiService.databaseErrorNotifier,
              builder: (context, hasDatabaseError, _) {
                final showOverlay = hasNoInternet || hasDatabaseError;
                return Stack(
                  children: [
                    if (child != null) child,
                    if (showOverlay)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: SafeArea(
                            child: RefreshIndicator(
                              onRefresh: () async {
                                try {
                                  final dio = Dio(
                                    BaseOptions(
                                      connectTimeout: const Duration(seconds: 5),
                                      receiveTimeout: const Duration(seconds: 5),
                                    ),
                                  );
                                  final base = await ApiService().getBaseUrl();
                                  final res = await dio.get('$base/login.php');
                                  // Got a response – server is up, clear both errors
                                  ApiService.noInternetNotifier.value = false;
                                  ApiService.databaseErrorNotifier.value = false;
                                  if (res.data != null) {
                                    final message = (res.data['message'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    if (message.contains('database connection failed')) {
                                      ApiService.databaseErrorNotifier.value = true;
                                    }
                                  }
                                } on DioException catch (e) {
                                  if (e.type == DioExceptionType.connectionError ||
                                      e.type == DioExceptionType.unknown ||
                                      e.type == DioExceptionType.receiveTimeout ||
                                      e.type == DioExceptionType.connectionTimeout) {
                                    // Still no internet
                                    ApiService.noInternetNotifier.value = true;
                                    ApiService.databaseErrorNotifier.value = false;
                                  } else {
                                    // Server responded but with an error – database issue
                                    ApiService.noInternetNotifier.value = false;
                                    ApiService.databaseErrorNotifier.value = true;
                                  }
                                } catch (_) {
                                  ApiService.noInternetNotifier.value = true;
                                  ApiService.databaseErrorNotifier.value = false;
                                }
                                await Future.delayed(
                                  const Duration(milliseconds: 300),
                                );
                              },
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                hasNoInternet
                                                    ? Icons.wifi_off_rounded
                                                    : Icons.cloud_off_rounded,
                                                size: 100,
                                                color: hasNoInternet
                                                    ? Colors.orange
                                                    : Colors.red,
                                              ),
                                              const SizedBox(height: 20),
                                              Text(
                                                hasNoInternet
                                                    ? 'No Internet Connection'
                                                    : 'Database Error',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 26,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.black,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                hasNoInternet
                                                    ? 'Please check your Wi-Fi or mobile data connection and pull down to retry.'
                                                    : 'The server database is currently unavailable. Please be patient and pull down to retry.',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
      home: const SplashScreen(),
    );
  }
}
