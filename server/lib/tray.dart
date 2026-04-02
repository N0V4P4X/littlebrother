import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'config.dart';
import 'http_server.dart';

class TrayManager {
  final ServerConfig config;
  HttpServer? _server;
  bool _isScanning = false;
  int _threatCount = 0;

  TrayManager(this.config);

  static TrayListener? _instance;

  Future<void> init() async {
    _instance = _TrayListener(onTrayIconClick: _onTrayIconClick);
    await trayManager.setIcon(_getTrayIconPath());
    await trayManager.setToolTip('LittleBrother Server');
    trayManager.addListener(_instance!);
    
    final menu = Menu(
      items: [
        MenuItem(
          key: 'open_dashboard',
          label: 'Open Dashboard',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'scan_status',
          label: 'Status: Idle',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'start_scan',
          label: 'Start Scanning',
        ),
        MenuItem(
          key: 'stop_scan',
          label: 'Stop Scanning',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    );
    
    await trayManager.setContextMenu(menu);
    
    trayManager.addListener(_TrayListener(onTrayIconClick: _onTrayIconClick));
  }

  String _getTrayIconPath() {
    // Use platform-appropriate icon path
    if (Platform.isLinux) {
      // Would need to bundle an icon - using a default
      return 'assets/tray_icon.png';
    }
    return 'assets/tray_icon.png';
  }

  void _onTrayIconClick() {
    // On Linux, tray click opens menu
    // Could open browser to dashboard
  }

  Future<void> startServer() async {
    _server = HttpServer(config);
    await _server!.start();
    print('Server started on port ${config.httpPort}');
  }

  void updateStatus({required bool isScanning, required int threats}) {
    _isScanning = isScanning;
    _threatCount = threats;
    
    // Update menu
    _updateMenu();
    
    // Update tooltip
    final tooltip = _isScanning 
        ? 'LittleBrother - Scanning (${_threatCount} threats)'
        : 'LittleBrother - Idle';
    trayManager.setToolTip(tooltip);
  }

  Future<void> _updateMenu() async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'open_dashboard',
          label: 'Open Dashboard',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'scan_status',
          label: _isScanning 
              ? 'Status: Scanning (${_threatCount} threats)'
              : 'Status: Idle',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'start_scan',
          label: 'Start Scanning',
          disabled: _isScanning ? true : false,
        ),
        MenuItem(
          key: 'stop_scan',
          label: 'Stop Scanning',
          disabled: _isScanning ? false : true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    );
    
    await trayManager.setContextMenu(menu);
  }

  void dispose() {
    if (_instance != null) {
      trayManager.removeListener(_instance!);
    }
  }
}

class _TrayListener implements TrayListener {
  final VoidCallback? onTrayIconClick;
  
  _TrayListener({this.onTrayIconClick});
  
  @override
  void onTrayIconMouseDown() {
    onTrayIconClick?.call();
  }
  
  @override
  void onTrayIconMouseUp() {}
  
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
  
  @override
  void onTrayIconRightMouseUp() {}
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // Handle menu item clicks
  }
}

class TrayMenuHandler {
  final Function(String)? onMenuItemClick;
  
  TrayMenuHandler({this.onMenuItemClick});
  
  void handle(String key) {
    switch (key) {
      case 'open_dashboard':
        _openDashboard();
        break;
      case 'start_scan':
        onMenuItemClick?.call('start_scan');
        break;
      case 'stop_scan':
        onMenuItemClick?.call('stop_scan');
        break;
      case 'quit':
        exit(0);
    }
  }
  
  Future<void> _openDashboard() async {
    // Open browser to dashboard
    if (Platform.isLinux) {
      Process.run('xdg-open', ['http://localhost:8080']);
    } else if (Platform.isMacOS) {
      Process.run('open', ['http://localhost:8080']);
    } else if (Platform.isWindows) {
      Process.run('start', ['http://localhost:8080']);
    }
  }
}
