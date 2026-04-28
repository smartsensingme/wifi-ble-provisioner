#include "esp_log.h"
// #include "freertos/FreeRTOS.h"
// #include "freertos/task.h"
#include "nvs_flash.h"
#include "wifi_ble_prov.h"
#include <stdio.h>

static const char *TAG = "APP_MAIN";

void app_main(void) {
  ESP_LOGI(TAG, "Inicializando o sistema...");

  // Inicialização do NVS: O wifi_provisioning depende obrigatoriamente do NVS
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
      err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS flash partition need to be erased. Erasing...");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  ESP_LOGI(TAG, "NVS inicializado com sucesso.");

  // Configuração da Struct utilizando o Macro Padrão
  prov_config_t config = WIFI_BLE_PROV_CONFIG_DEFAULT();
  // Exemplo de como você poderia sobrescrever as opções dinamicamente:
  // config.service_name_prefix = "COFRE_ESP_";
  // config.status_led_pin = GPIO_NUM_4;

  ESP_LOGI(TAG, "Chamando a rotina start_wifi_provisioning...");

  // Chamada de Inicialização com Error Check
  ESP_ERROR_CHECK(start_wifi_provisioning(&config));

  ESP_LOGI(TAG, "Boot principal concluído. Sistema aguardando eventos...");
}
