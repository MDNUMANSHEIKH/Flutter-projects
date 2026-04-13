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
          valueListenable: ApiService.databaseErrorNotifier,
          builder: (context, hasDatabaseError, _) {
            return Stack(
              children: [
                if (child != null) child,
                if (hasDatabaseError)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: SafeArea(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            try {
                              final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 3), receiveTimeout: const Duration(seconds: 3)));
                              final base = await ApiService().getBaseUrl();
                              final res = await dio.get('$base/login.php');
                              if (res.data != null) {
                                final message = (res.data['message'] ?? '').toString().toLowerCase();
                                if (message.contains('connection error') || message.contains('database connection failed')) {
                                  ApiService.databaseErrorNotifier.value = true;
                                } else {
                                  ApiService.databaseErrorNotifier.value = false;
                                }
                              }
                            } catch (_) {
                              // Ensure it stays true if the connection fails
                              ApiService.databaseErrorNotifier.value = true;
                            }
                            await Future.delayed(const Duration(milliseconds: 300));
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
                                          Image.asset('img/sad-face.png', height: 180),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Database Error\nBe Paitent',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black,
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
      home: const SplashScreen(),
    );
  }
}
