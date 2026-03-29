class OpsecController {
  Future<void> init() async {}

  bool get canKillRf => false;

  Future<String> killRf() async {
    return 'RF kill not available on this platform';
  }

  Future<String> restoreRf() async {
    return 'RF restore not available on this platform';
  }

  Future<void> requestWriteSettingsPermission() async {}
}
