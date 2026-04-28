# ESP32 Firmware: BLE WiFi Provisioner

## Visão Geral

Este firmware transforma o ESP32 em um nó capaz de receber credenciais de rede de forma segura via BLE (Bluetooth Low Energy). Ele utiliza o componente nativo `wifi_provisioning` da ESP-IDF para gerenciar a segurança e o transporte dos dados via Protocol Buffers.

## Requisitos Técnicos

* **Framework:** ESP-IDF v6.x
* **Linguagem:** C
* **Driver de Provisionamento:** `esp_prov` (Unified Provisioning)
* **Esquema de Segurança:** Security 1 (Sec1) com PoP (Proof of Possession)
* **Persistência:** NVS (Non-Volatile Storage) para armazenamento do SSID/Senha.

## Arquitetura do Componente

O firmware deve ser modularizado para que a lógica de provisionamento seja independente da lógica de negócio.

### 1. Inicialização Dinâmica (Hardware Abstraction)

Seguindo as diretrizes de projeto, a inicialização do componente de provisionamento **não deve usar pinos hardcoded**. O desenvolvedor deve passar uma estrutura de configuração para a função de inicialização:

```c
typedef struct {
    gpio_num_t provision_button_pin; // Pino para o gatilho manual (long press)
    gpio_num_t status_led_pin;       // Pino para feedback visual
    uint16_t long_press_duration_ms; // Tempo para reset/provisionamento
    const char *service_name_prefix; // Prefixo do dispositivo (ex: "PROV_ESP32_")
} prov_config_t;

// Macro facilitadora
#define WIFI_BLE_PROV_CONFIG_DEFAULT() { ... }

esp_err_t start_wifi_provisioning(prov_config_t *config);
```

### 2. Configuração de UUID via Kconfig (Casamento de Segurança)

O ecossistema Bluetooth Low Energy (BLE) utiliza Service UUIDs para identificar o tipo de serviço que o hardware está oferecendo no ar. A Espressif define um UUID padrão global para o modo de provisionamento (`1775244d-6b43-439b-877c-060f2d9bed07`).

**Para que o UUID é usado?**
O UUID funciona como um "Uniforme de Trabalho" da placa. Quando o aplicativo Flutter realiza o escaneamento nativo, ele procura exclusivamente por esse "Uniforme" para não perder tempo conectando em TVs, smartwatches ou produtos de terceiros genéricos.

**Como customizar e "Casar" os sistemas:**
Para evitar que dispositivos genéricos interfiram no provisionamento do seu produto comercial, o Service UUID do BLE foi externalizado para o `Kconfig`, isolando o seu ecossistema. 
O firmware do ESP32 e o aplicativo Flutter precisam estar em perfeita sincronia:
1. **No Firmware:** No terminal, execute `idf.py menuconfig` e navegue até **Wi-Fi BLE Provisioner Configuration**. Se você definir um UUID próprio (ex: `11223344-5566-7788-9900-aabbccddeeff`), a compilação irá automaticamente injetar `#define CONFIG_PROV_CUSTOM_UUID` e o firmware passará a usar esse UUID em vez do padrão.
2. **No Flutter:** Abra o arquivo `lib/config.dart` e atualize a variável `AppConfig.bleProvisioningUuid` com o exato mesmo valor.

### 3. Máquina de Estados e Gatilhos

O sistema entra em modo de provisionamento sob duas condições:

1. **Ausência de Credenciais:** Se após o boot o NVS não retornar credenciais válidas ou falhar na conexão por X tentativas.

2. **Gatilho Manual (Long Press):** Se o pino configurado em `provision_button_pin` for mantido em nível lógico alto por um intervalo configurável (3-5 segundos).

## Fluxo de Operação

1. **Power On Self Test (POST):** Verifica integridade do NVS.

2. **WiFi Scan/Connect:** Tenta conectar com as últimas credenciais salvas.

3. **Aguardar Provisionamento:** Se falhar ou o botão for pressionado, inicia o anúncio BLE (Advertising) com o nome `PROV_ESP32_XXXX`.

4. **Handshake Sec1:** O app Linux inicia o túnel seguro via ECDH.

5. **Data Exchange:** Recebe SSID/Senha e tenta conectar. Em caso de sucesso, salva no NVS e encerra o BLE.

## Instruções para o Agente de IA (Codificação)

Ao implementar este firmware, o agente deve:

- Utilizar `esp_event_loop` para capturar os eventos de `WIFI_PROV_EVENT`.

- Implementar o **Proof of Possession (PoP)** para evitar conexões não autorizadas durante o pareamento.

- Garantir que o driver do botão utilize interrupções ou uma task dedicada com *debounce* para não bloquear a execução principal.

- Seguir o padrão de nomes de componentes da ESP-IDF, separando `wifi_manager`, `ble_prov_transport` e `led_indicator`.

## Como Compilar e Gravar

Certifique-se de que o ambiente da ESP-IDF v6 está carregado no terminal:

```bash
# Navegar até a pasta do firmware
cd esp32_firmware

# Configurar o target (ex: esp32, esp32s3)
idf.py set-target esp32

# Compilar, gravar e abrir o monitor serial
idf.py build flash monitor
```

---
![SmartSensing.me Logo](https://smartsensing.me/ssme-logo.png)

## 📝 Descrição

Este projeto faz parte do ecossistema **SmartSensing.me** e vai além dos exemplos básicos encontrados na internet. Aqui, aplicamos os fundamentos reais da engenharia de instrumentação e sistemas embarcados de alta performance.

Diferente de conteúdos superficiais voltados apenas para cliques, este repositório entrega:
- **Ineditismo:** Implementações originais baseadas em quase 30 anos de experiência acadêmica.
- **Densidade Técnica:** Uso profissional do framework ESP-IDF e FreeRTOS.
- **Didática:** Código documentado e estruturado para quem busca evolução técnica real.

> "Transformamos sinais do mundo físico em inteligência digital, sem atalhos."

---

## 🛠️ Tecnologias
- **Hardware Target:** ESP32 / ESP32-S3
- **Framework:** ESP-IDF v5.x
- **Linguagem:** C / C++
- **Simulação:** LTSpice (Modelagem de Sensores)

---

## 👤 Sobre o Autor

**José Alexandre de França** *Professor Adjunto no Departamento de Engenharia Elétrica da UEL*

Engenheiro Eletricista com quase três décadas de experiência no ensino de graduação e pós-graduação. Doutor em Engenharia Elétrica, pesquisador em instrumentação eletrônica e desenvolvedor de sistemas embarcados. O SmartSensing.me é o meu compromisso de elevar o nível da educação tecnológica no Brasil.

- 🌐 **Website:** [smartsensing.me](https://smartsensing.me)
- 📧 **E-mail:** [info@smartsensing.me](mailto:info@smartsensing.me)
- 📺 **YouTube:** [@smartsensingme](https://youtube.com/@smartsensingme)
- 📸 **Instagram:** [@smartsensing.me](https://instagram.com/smartsensing.me)

---

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.