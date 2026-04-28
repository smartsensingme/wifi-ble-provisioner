idf_component_register(SRCS "wifi_ble_prov.c"
                    INCLUDE_DIRS "include"
                    REQUIRES network_provisioning nvs_flash esp_netif esp_event esp_driver_gpio esp_timer)
