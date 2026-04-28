# Flutter App: BLE WiFi Provisioner

## Visão Geral
Este é o aplicativo responsável por atuar como o "Provisionador" na arquitetura. Desenvolvido em Flutter com suporte nativo multiplataforma, ele foi homologado para **Linux Desktop** e **Android**. Sua função é escanear o ambiente em busca de dispositivos ESP32 em modo de pareamento, estabelecer uma conexão segura e enviar as credenciais de Wi-Fi.

## Requisitos de Ambiente
* **Framework:** Flutter SDK (Suporte a Linux Desktop e Android ativados)
* **Linguagem:** Dart
* **Stack Bluetooth:** BlueZ (Linux) / Android Bluetooth API (Mobile)
* **Protocolo de Dados:** Protocol Buffers (Protobuf)

## Pré-requisitos do Sistema (Multiplataforma)

### Para Linux Desktop (Ubuntu/Debian)
Para que o Flutter consiga interagir com o hardware Bluetooth do Linux sem exigir privilégios de superusuário (`sudo`), o ambiente do desenvolvedor/usuário final deve estar pré-configurado:
1. O usuário deve pertencer aos grupos apropriados: `sudo usermod -aG bluetooth $USER`
2. O serviço BlueZ deve estar ativo e desbloqueado: `sudo rfkill unblock bluetooth`
3. É necessário realizar *logout* e *login* após alterar os grupos de usuário.

### Para Android
O aplicativo já solicita permissões de `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, e `ACCESS_FINE_LOCATION` nativamente em tempo de execução. O desenvolvedor só precisa garantir:
1. Aparelho com Android 5.0 (API 21) ou superior.
2. Localização física habilitada no aparelho (requisito do Google para BLE e para leitura do Wi-Fi atual via `network_info_plus`).

## Arquitetura de Software
O aplicativo é dividido nas seguintes camadas lógicas:

1. **Interface Gráfica (UI):** Telas para listar dispositivos descobertos (`PROV_ESP32_...`), formulário para inserção de SSID/Senha e feedback visual.
2. **Camada BLE:** Utilização de `flutter_blue_plus` para gerenciar scan nativo, conexão GATT, e negociação de MTU de forma otimizada para cada sistema operacional.
3. **Camada de Provisionamento (`esp_prov`):**
    * Handshake criptográfico (Security 1) e validação de Proof of Possession (PoP).
    * Comunicação Protobuf estrita usando a biblioteca central `ssme_esp_provisioning`.

### Diferenças de UX por Plataforma (Wi-Fi Scan)
Uma grande diferença arquitetural implementada no app é como ele obtém a lista de Wi-Fi para o usuário:
* **No Linux (Desktop):** Assim que a conexão BLE é estabelecida, o aplicativo envia um comando (via Protobuf) pedindo para a **própria placa ESP32 escanear o ambiente** e devolver a lista de roteadores ao seu redor. Isso é feito porque um PC Desktop costuma estar conectado via cabo, e o que importa é o que a placa está "enxergando" lá na bancada.
* **No Android (Mobile):** Fazer a placa ESP32 escanear as redes Wi-Fi e transmitir essa lista gigante via Bluetooth simultaneamente congestiona a banda e frequentemente causa quedas de conexão no rádio BLE do celular. Para garantir estabilidade extrema, o Android usa a biblioteca `network_info_plus` para ler silenciosamente em qual Wi-Fi o seu celular já está conectado e **preenche automaticamente** o SSID no formulário.

## Casamento de UUID (Segurança e Isolamento)
O ecossistema Bluetooth Low Energy (BLE) utiliza Service UUIDs para identificar o tipo de serviço que o hardware está oferecendo no ar. A Espressif define um UUID padrão global para o modo de provisionamento unificado (`1775244d-6b43-439b-877c-060f2d9bed07`).

**Para que o UUID é usado?**
O UUID funciona como um "Uniforme de Trabalho" da placa. Quando o aplicativo Flutter realiza o escaneamento nativo, ele procura exclusivamente por esse "Uniforme" para não perder tempo conectando em TVs, smartwatches ou produtos de terceiros.

**Como customizar e "Casar" os sistemas:**
Para produtos comerciais, você **deve** substituir o UUID padrão por um UUID exclusivo da sua marca, isolando o seu ecossistema. 
O aplicativo Flutter e o firmware do ESP32 precisam estar em perfeita sincronia:
1. **No Firmware:** Defina o UUID usando `idf.py menuconfig` (aba *Wi-Fi BLE Provisioner Configuration*).
2. **No Flutter:** Abra o arquivo `lib/config.dart` e atualize a variável `AppConfig.bleProvisioningUuid` com o exato mesmo valor.

## Instruções para o Agente de IA (Codificação)
Ao desenvolver as funcionalidades deste aplicativo, o agente deve seguir estritamente estas diretrizes:

* **Tratamento de Exceções do BlueZ:** O ecossistema Bluetooth no Linux pode apresentar timeouts ou dispositivos "fantasmas" em cache. Implemente *try/catch* robustos nas chamadas D-Bus/BLE e forneça logs detalhados no console para facilitar o debug.
* **Protobuf em Dart:** Não tente enviar credenciais em strings de texto plano. O agente deve gerar as classes Dart a partir dos arquivos `.proto` oficiais da Espressif (fornecidos pelo componente `wifi_provisioning`) e utilizá-los para envelopar as mensagens.
* **Isolamento de Estado:** Utilize uma gerência de estado adequada (como Provider, Riverpod ou BLoC) para garantir que a UI não trave durante o escaneamento BLE ou durante a negociação criptográfica (Handshake Sec1), que são operações assíncronas.
* **Desconexão Limpa:** Ao finalizar o provisionamento com sucesso ou falha, o app deve enviar o comando de desconexão e limpar os recursos do BLE local para evitar travamento do módulo do kernel (`btusb`).

## Como Rodar o Projeto

1.  **Instalar dependências do sistema:**
    ```bash
    sudo apt-get install clang cmake git ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
    ```
2.  **Obter pacotes do Flutter:**
    ```bash
    flutter pub get
    ```
3.  **Gerar arquivos Protobuf (se necessário):**
    ```bash
    # Requer o compilador protoc instalado no sistema
    protoc --dart_out=grpc:lib/src/generated -Iprotos protos/*.proto
    ```
4.  **Executar o aplicativo:**
    ```bash
    flutter run -d linux
    ```

## Aviso Importante sobre Licenciamento (Uso Comercial)

No projeto de exemplo (aplicativo desktop Linux) que utiliza o pacote `ssme_esp_provisioning`, a interface de abstração Bluetooth foi construída utilizando o plugin genérico **`flutter_blue_plus`**.

Recentemente, a biblioteca principal `flutter_blue_plus` **mudou seu modelo de licenciamento**. A partir de certas versões recentes (2.x+), eles adicionaram exigências de telemetria ou pagamento de licença comercial para aplicativos de código fechado. Como reflexo, os métodos de conexão requerem um parâmetro exato de licença (`license: License.free`), forçando o uso não comercial da biblioteca.

### Alternativa Gratuita para Uso Comercial (MIT License)
Como o pacote `ssme_esp_provisioning` conta com a interface genérica de transporte (`ProvTransport`), você **NÃO** é obrigado a usar o `flutter_blue_plus`! O provisionador em si continua sendo Apache/Open Source.

Se você planeja lançar um aplicativo comercial e sem restrições de licença, é fortemente recomendado que você substitua o `flutter_blue_plus` no aplicativo. **A alternativa sugerida é o pacote [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble)**:
* É coberto integralmente pela **Licença MIT** (livre para todo tipo de uso comercial, fechado ou open-source).
* É robusto e muito estável na comunicação GATT (o que reduz problemas de `Operation failed with ATT error` e perda de conexão durante o handshake).
* É facilmente integrável apenas reescrevendo o arquivo `ble_transport.dart` para estender `ProvTransport` usando as funções do novo plugin.

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