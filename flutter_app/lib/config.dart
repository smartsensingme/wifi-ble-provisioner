class AppConfig {
  /// O UUID do Serviço de Provisionamento BLE.
  /// Este valor DEVE corresponder ao configurado no firmware do ESP32 via menuconfig (CONFIG_PROV_CUSTOM_UUID).
  /// O valor padrão oficial da Espressif é "1775244d-6b43-439b-877c-060f2d9bed07".
  static const String bleProvisioningUuid = "1775244d-6b43-439b-877c-060f2d9bed07";
}
