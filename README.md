# WiFi-BLE Provisioner (Monorepo)

## Visão Geral do Projeto

Este projeto é um sistema de provisionamento de credenciais Wi-Fi (SSID e Senha) para dispositivos ESP32 através de uma conexão Bluetooth Low Energy (BLE). A arquitetura é dividida em dois componentes principais: um aplicativo multiplataforma (Android e Linux Desktop) e um firmware embarcado para o ESP32.

O objetivo é fornecer uma interface gráfica segura e amigável para escanear dispositivos próximos e transmitir as credenciais para o hardware, que por sua vez, deve gerenciar as tentativas de conexão e salvar os dados de forma persistente.

## Arquitetura e Tecnologias

A solução adota a stack oficial de **Unified Provisioning (`esp_prov`)** da Espressif, garantindo segurança na troca de dados via BLE.

* **Firmware (ESP32):** Desenvolvido em C utilizando o framework **ESP-IDF v6**.
* **Software (Multiplataforma):** Desenvolvido em **Flutter** para rodar nativamente em dispositivos Android e desktops Linux.
* **Protocolo de Comunicação:** BLE (Bluetooth Low Energy) envelopando payloads em Protocol Buffers (Protobuf).
* **Segurança:** Esquema Security 1 (Sec1) com troca de chaves via Curva Elíptica (ECDH) e Proof of Possession (PoP).

## Estrutura do Monorepo

O repositório está dividido em duas pastas estritas. O código de uma pasta não deve interferir ou ter dependências diretas de compilação com a outra.

```text
wifi-ble-provisioner/
├── README.md                  # Este documento (Visão geral e regras do monorepo)
├── esp32_firmware/            # Projeto ESP-IDF (C)
│   ├── README.md              # Documentação específica do firmware
│   ├── CMakeLists.txt
│   ├── main/                  # Ponto de entrada e máquina de estados
│   └── components/            # Lógica de botão, controle de LED e gerenciador Wi-Fi
└── flutter_app/                 # Projeto Flutter (Dart)
    ├── README.md              # Documentação específica do app (Linux/Android)
    ├── pubspec.yaml
    ├── lib/                   # UI e lógica de comunicação BLE/Protobuf
    ├── android/               # Runner específico para Android
    └── linux/                 # Runner específico para Linux
```

## Regras e Diretrizes para Agentes de IA

Para o desenvolvimento assistido por IA, as seguintes diretrizes devem ser estritamente seguidas:

1. **Separação de Contexto:** Ao alterar o código do aplicativo Flutter, o contexto do firmware ESP32 deve ser considerado apenas para fins de protocolo (Protobuf e UUIDs do BLE). Não sugira integrações que quebrem o isolamento das pastas.

2. **Segurança e Protocolo:** O uso de texto plano para credenciais é proibido. Toda comunicação de provisionamento deve obrigatoriamente utilizar o padrão `esp_prov` com Sec1.

3. **Gatilhos de Hardware Dinâmicos:** No firmware, a inicialização do modo de provisionamento deve ocorrer caso nenhuma rede conhecida seja encontrada e mediante o acionamento de um botão físico (Long Press de 3 a 5 segundos). Os pinos de I/O não devem ser configurados de forma *hardcoded*, permitindo injeção de dependência na inicialização do componente para facilitar futuras trocas de hardware.

4. **Estabilidade e Fallbacks:** O código focado em BLE deve prever tratamento robusto de exceções. Em ambientes hostis (como o BlueZ do Linux), o código deve prover fallbacks inteligentes (ex: filtrar pelo MAC caso o nome falhe). Comportamentos de UX também devem se adaptar à plataforma (ex: scan ativo no Linux vs Auto-preenchimento silencioso no Android).

5. **Casamento de UUIDs:** Para blindar o ecossistema, o Service UUID do modo de provisionamento não é hardcoded em lógicas obscuras. Ao criar um produto, o UUID DEVE ser alinhado usando as ferramentas oficias de cada ecossistema: `idf.py menuconfig` (no firmware) e `lib/config.dart` (no aplicativo Flutter).

## Como Iniciar

Cada subprojeto possui seu próprio guia de configuração, dependências e build.

- Para compilar e gravar o firmware, consulte: `/esp32_firmware/README.md`

- Para rodar e compilar a interface gráfica, consulte: `/flutter_app/README.md`

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