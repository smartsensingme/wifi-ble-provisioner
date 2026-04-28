#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "network_provisioning/manager.h"
#include "network_provisioning/scheme_ble.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "wifi_ble_prov.h"

// Configuração de polaridade do LED
// A maioria das placas customizadas com ESP32 usa Active-Low (0 = Ligado, 1 = Desligado).
// Se o seu LED for Active-High (1 = Ligado, 0 = Desligado), apenas inverta os valores abaixo.
#define LED_OFF_STATE 0
#define LED_ON_STATE  1

static const char *TAG = "WIFI_PROV";

/**
 * @brief Enumeração para representar os possíveis estados do LED de status.
 */
typedef enum {
    LED_STATE_IDLE,         /*!< Estado inicial/ocioso. LED permanece apagado. */
    LED_STATE_PROV_ACTIVE,  /*!< Provisionamento BLE ativo. LED piscará para indicar modo de pareamento. */
    LED_STATE_CONNECTED,    /*!< Wi-Fi conectado com sucesso. LED permanecerá apagado. */
    LED_STATE_ERROR         /*!< Erro/Desconectado. LED permanecerá apagado. */
} app_led_state_t;

static app_led_state_t current_led_state = LED_STATE_IDLE;
static esp_timer_handle_t global_led_timer = NULL;
static bool blink_state = false;
static gpio_num_t global_led_pin = GPIO_NUM_NC;

/**
 * @brief Atualiza a máquina de estados do LED baseada no ciclo de vida da rede.
 * 
 * Gerencia o esp_timer responsável por piscar o LED e altera o nível
 * lógico do GPIO dependendo se o sistema está ocioso, provisionando ou conectado.
 * 
 * @param new_state Novo estado a ser aplicado no hardware do LED.
 */
static void update_led_state(app_led_state_t new_state) {
    if (global_led_pin == GPIO_NUM_NC) return;
    current_led_state = new_state;

    if (new_state == LED_STATE_CONNECTED) {
        if (global_led_timer) esp_timer_stop(global_led_timer);
        gpio_set_level(global_led_pin, LED_OFF_STATE); // Apagado
    } else if (new_state == LED_STATE_ERROR) {
        if (global_led_timer) esp_timer_stop(global_led_timer);
        gpio_set_level(global_led_pin, LED_OFF_STATE); // Apagado
    } else if (new_state == LED_STATE_PROV_ACTIVE) {
        if (global_led_timer) {
            esp_timer_stop(global_led_timer);
            esp_timer_start_periodic(global_led_timer, 500000); // Piscar a cada 500ms
        }
    } else if (new_state == LED_STATE_IDLE) {
        if (global_led_timer) esp_timer_stop(global_led_timer);
        gpio_set_level(global_led_pin, LED_OFF_STATE); // Apagado
    }
}

/**
 * @brief Callback periódica do timer de hardware (esp_timer).
 * 
 * Chamada a cada 500ms durante o modo de provisionamento ativo,
 * inverte o nível lógico do pino para criar o efeito visual de "piscar".
 */
static void led_timer_cb(void *arg) {
    if (global_led_pin != GPIO_NUM_NC && current_led_state == LED_STATE_PROV_ACTIVE) {
        gpio_set_level(global_led_pin, blink_state ? LED_ON_STATE : LED_OFF_STATE);
        blink_state = !blink_state;
    }
}

/**
 * @brief Handler centralizado para os eventos da stack de Rede e Provisionamento.
 * 
 * Esta função recebe e avalia callbacks do Wi-Fi (conexão, desconexão, obtenção de IP)
 * e do manager de provisionamento (início, credenciais recebidas, falhas, etc.),
 * fazendo o roteamento para a máquina de estados do LED.
 */
static void prov_event_handler(void* arg, esp_event_base_t event_base,
                               int32_t event_id, void* event_data)
{
    if (event_base == NETWORK_PROV_EVENT) {
        switch (event_id) {
            case NETWORK_PROV_START:
                ESP_LOGI(TAG, "Provisioning started");
                update_led_state(LED_STATE_PROV_ACTIVE);
                break;
            case NETWORK_PROV_WIFI_CRED_RECV: {
                wifi_sta_config_t *wifi_sta_cfg = (wifi_sta_config_t *)event_data;
                ESP_LOGI(TAG, "Received Wi-Fi credentials"
                         "\n\tSSID     : %s\n\tPassword : %s",
                         (const char *) wifi_sta_cfg->ssid,
                         (const char *) wifi_sta_cfg->password);
                break;
            }
            case NETWORK_PROV_WIFI_CRED_FAIL: {
                network_prov_wifi_sta_fail_reason_t *reason = (network_prov_wifi_sta_fail_reason_t *)event_data;
                ESP_LOGE(TAG, "Provisioning failed!\n\tReason : %s"
                         "\n\tPlease reset to factory and retry provisioning",
                         (*reason == NETWORK_PROV_WIFI_STA_AUTH_ERROR) ?
                         "Wi-Fi station authentication failed" : "Wi-Fi access-point not found");
                update_led_state(LED_STATE_ERROR);
                break;
            }
            case NETWORK_PROV_WIFI_CRED_SUCCESS:
                ESP_LOGI(TAG, "Provisioning successful");
                break;
            case NETWORK_PROV_END:
                ESP_LOGI(TAG, "Provisioning end");
                update_led_state(LED_STATE_CONNECTED);
                network_prov_mgr_deinit();
                break;
            default:
                break;
        }
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "Connected with IP Address:" IPSTR, IP2STR(&event->ip_info.ip));
        update_led_state(LED_STATE_CONNECTED);
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGI(TAG, "Disconnected. Connecting to the AP again...");
        update_led_state(LED_STATE_ERROR);
        esp_wifi_connect();
    }
}

/**
 * @brief Tarefa FreeRTOS dedicada ao monitoramento contínuo do botão físico.
 * 
 * Aplica uma lógica simples de debounce e contagem de tempo (long press).
 * Se o tempo pressionado ultrapassar `long_press_duration_ms`, as credenciais
 * são apagadas do NVS e o chip é reiniciado (Factory Reset).
 */
static void button_monitor_task(void *arg) {
    prov_config_t *config = (prov_config_t *)arg;
    uint32_t press_duration = 0;
    const uint32_t poll_interval_ms = 100;

    gpio_set_direction(config->provision_button_pin, GPIO_MODE_INPUT);
    gpio_set_pull_mode(config->provision_button_pin, GPIO_PULLUP_ONLY);

    while (1) {
        if (gpio_get_level(config->provision_button_pin) == 0) {
            press_duration += poll_interval_ms;
            if (press_duration >= config->long_press_duration_ms) {
                ESP_LOGI(TAG, "Button long press detected. Resetting provisioning...");
                update_led_state(LED_STATE_ERROR);
                network_prov_mgr_reset_wifi_provisioning();
                vTaskDelay(pdMS_TO_TICKS(1000));
                esp_restart();
            }
        } else {
            press_duration = 0;
        }
        vTaskDelay(pdMS_TO_TICKS(poll_interval_ms));
    }
}

/**
 * @brief Inicializa e expõe a rotina principal de provisionamento Wi-Fi.
 * 
 * Coordena toda a configuração básica necessária (NVS, esp_netif, esp_wifi), 
 * o feedback visual de hardware (LEDs), o gatilho físico (Botão) e, finalmente,
 * gerencia a camada do `esp_prov` para expor o servidor GATT Bluetooth se não
 * houver credenciais armazenadas previamente.
 * 
 * @param config Estrutura prov_config_t com as configurações de GPIOs e prefixos.
 * @return esp_err_t Retorna ESP_OK se toda a rotina foi inicializada com sucesso.
 */
esp_err_t start_wifi_provisioning(prov_config_t *config)
{
    ESP_LOGI(TAG, "Starting component initialization...");

    // 1. Inicializacao Base (NVS e Rede)
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    // 2. Feedback Visual (LED Simples em GPIO)
    global_led_pin = config->status_led_pin;
    gpio_reset_pin(global_led_pin);
    gpio_set_direction(global_led_pin, GPIO_MODE_OUTPUT);
    gpio_set_level(global_led_pin, LED_OFF_STATE); // Apagado por padrão

    // Configurar timer para o efeito de "Piscar"
    esp_timer_create_args_t timer_args = {
        .callback = led_timer_cb,
        .arg = NULL,
        .dispatch_method = ESP_TIMER_TASK,
        .name = "led_timer"
    };
    esp_timer_create(&timer_args, &global_led_timer);

    // 3. Gatilho de Hardware (Task de monitoramento com debounce)
    prov_config_t *task_config = malloc(sizeof(prov_config_t));
    if (task_config) {
        *task_config = *config;
        xTaskCreate(button_monitor_task, "button_monitor", 2048, task_config, 5, NULL);
    } else {
        ESP_LOGE(TAG, "Failed to allocate memory for button task config");
        return ESP_ERR_NO_MEM;
    }

    // Registrar Handlers no Event Loop para Feedback Visual e fluxo Wi-Fi
    ESP_ERROR_CHECK(esp_event_handler_register(NETWORK_PROV_EVENT, ESP_EVENT_ANY_ID, &prov_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &prov_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &prov_event_handler, NULL));

    // 4. Lógica do esp_prov (Unified Provisioning via BLE)
    network_prov_mgr_config_t prov_mgr_config = {
        .scheme = network_prov_scheme_ble,
        .scheme_event_handler = NETWORK_PROV_EVENT_HANDLER_NONE
    };
    ESP_ERROR_CHECK(network_prov_mgr_init(prov_mgr_config));

    bool provisioned = false;
    ESP_ERROR_CHECK(network_prov_mgr_is_wifi_provisioned(&provisioned));

    if (!provisioned) {
        ESP_LOGI(TAG, "Device not provisioned. Starting BLE provisioning...");
        update_led_state(LED_STATE_PROV_ACTIVE);
        
        uint8_t mac[6];
        ESP_ERROR_CHECK(esp_wifi_get_mac(WIFI_IF_STA, mac));
        
        // Criar dinamicamente o Service Name configurável (Padrão: PROV_ESP32_XXXX)
        char service_name[32];
        const char *prefix = (config->service_name_prefix) ? config->service_name_prefix : "PROV_ESP32_";
        snprintf(service_name, sizeof(service_name), "%s%02X%02X", prefix, mac[4], mac[5]);

        // Criar dinamicamente o Proof of Possession (PoP): XXXX
        char pop[5];
        snprintf(pop, sizeof(pop), "%02X%02X", mac[4], mac[5]);
        
        network_prov_security_t security = NETWORK_PROV_SECURITY_1;
        
        // Configurar UUID Customizado se definido no Kconfig
#ifdef CONFIG_PROV_CUSTOM_UUID
        const char *custom_uuid_str = CONFIG_PROV_CUSTOM_UUID;
        if (strlen(custom_uuid_str) == 36) { // Tamanho exato de um UUID padrão
            uint8_t custom_uuid[16];
            unsigned int u[16];
            // O ESP-IDF exige o UUID em formato Little-Endian (invertido)
            if (sscanf(custom_uuid_str, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                &u[15], &u[14], &u[13], &u[12], &u[11], &u[10], &u[9], &u[8],
                &u[7], &u[6], &u[5], &u[4], &u[3], &u[2], &u[1], &u[0]) == 16) {
                
                for(int i = 0; i < 16; i++) {
                    custom_uuid[i] = (uint8_t)u[i];
                }
                ESP_LOGI(TAG, "Using custom BLE Service UUID: %s", custom_uuid_str);
                network_prov_scheme_ble_set_service_uuid(custom_uuid);
            } else {
                ESP_LOGE(TAG, "Invalid Custom UUID format in Kconfig. Using ESP-IDF default.");
            }
        }
#endif

        ESP_ERROR_CHECK(network_prov_mgr_start_provisioning(security, pop, service_name, NULL));
        
        ESP_LOGI(TAG, "Provisioning Started.");
        ESP_LOGI(TAG, "BLE Device Name: %s", service_name);
        ESP_LOGI(TAG, "PoP (Proof of Possession): %s", pop);
    } else {
        ESP_LOGI(TAG, "Already provisioned. Starting Wi-Fi directly.");
        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
        ESP_ERROR_CHECK(esp_wifi_start());
    }

    return ESP_OK;
}
