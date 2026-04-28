#pragma once

#include "driver/gpio.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Configuração dinâmica para o provisionamento Wi-Fi via BLE.
 * Conforme as diretrizes arquiteturais, os pinos não devem ser hardcoded.
 */
typedef struct {
  gpio_num_t provision_button_pin; // Pino para o gatilho manual (long press)
  gpio_num_t status_led_pin;       // Pino para feedback visual do status
  uint16_t long_press_duration_ms; // Tempo de pressionamento longo (ex:
                                   // 3000-5000 ms)
  const char *service_name_prefix; // Prefixo do nome do dispositivo BLE (ex:
                                   // "PROV_ESP32_")
} prov_config_t;

/**
 * @brief Inicializa e gerencia o provisionamento Wi-Fi e a conectividade.
 *
 * Inicia o modo de provisionamento se as credenciais não estiverem
 * presentes ou se o gatilho manual (botão) for acionado.
 *
 * @param config Ponteiro para a estrutura de configuração dinâmica.
 * @return esp_err_t ESP_OK em caso de sucesso ou código de erro em falha.
 */
esp_err_t start_wifi_provisioning(prov_config_t *config);

#define WIFI_BLE_PROV_CONFIG_DEFAULT()                                         \
  {.provision_button_pin = GPIO_NUM_0,                                         \
   .status_led_pin = GPIO_NUM_4,                                               \
   .long_press_duration_ms = 3000,                                             \
   .service_name_prefix = "PROV_ESP32_"}

#ifdef __cplusplus
}
#endif
