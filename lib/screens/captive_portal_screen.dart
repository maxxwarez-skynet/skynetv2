import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';

class CaptivePortalScreen extends StatefulWidget {
  final String url;
  final Function onSetupComplete;

  const CaptivePortalScreen({
    super.key,
    required this.url,
    required this.onSetupComplete,
  });

  @override
  State<CaptivePortalScreen> createState() => _CaptivePortalScreenState();
}

class _CaptivePortalScreenState extends State<CaptivePortalScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loadError = false;
  Timer? _responseCheckTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _responseCheckTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            
            // Start checking for 202 response after page loads
            _startResponseCheck();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _loadError = true;
            });
          },
          // Handle navigation events to detect when setup is complete
          onNavigationRequest: (NavigationRequest request) {
            // Check for HTTP status code in the URL (some WebViews encode this in the URL)
            if (request.url.contains('/?status=202') || request.url.contains('&status=202')) {
              // If we detect a 202 status code, setup is complete
              widget.onSetupComplete();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }
  
  // Start a timer to periodically check for 202 response
  void _startResponseCheck() {
    // Cancel any existing timer
    _responseCheckTimer?.cancel();
    
    // Create a new timer that checks every 2 seconds
    _responseCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkForSetupComplete();
    });
  }
  
  // Check if setup is complete by running JavaScript
  Future<void> _checkForSetupComplete() async {
    try {
      // Inject JavaScript to check the current page's status code
      // This is a workaround since WebView doesn't directly expose HTTP status codes
      final String? result = await _controller.runJavaScriptReturningResult(
        'document.body.textContent.includes("202") || '
        'document.body.textContent.includes("success") || '
        'document.body.textContent.includes("complete")'
      ) as String?;
      
      if (result == 'true') {
        // If we find success indicators in the page content, consider setup complete
        _responseCheckTimer?.cancel();
        widget.onSetupComplete();
      }
    } catch (e) {
      // Ignore errors during JavaScript execution
      debugPrint('Error checking for setup complete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Setup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_loadError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 60,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load the setup page',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Make sure you are connected to the device WiFi',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      _controller.reload();
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Call the callback to indicate setup is complete
                  widget.onSetupComplete();
                },
                child: const Text('Setup Complete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}