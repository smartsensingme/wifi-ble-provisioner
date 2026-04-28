import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ssme_esp_provisioning/ssme_esp_provisioning.dart';

class BleTransport implements ProvTransport {
  final BluetoothDevice device;
  Map<String, BluetoothCharacteristic> _endpoints = {};

  BleTransport(this.device);

  @override
  Future<bool> connect() async {
    if (device.isDisconnected) {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15), license: License.free);
      
      // Forçar negociação de MTU no Linux/Android para evitar timeouts de pacotes longos
      try {
        await device.requestMtu(256);
        debugPrint('MTU de 256 bytes requisitado com sucesso.');
      } catch (e) {
        debugPrint('Aviso ao requisitar MTU: $e');
      }
    }
    
    // Mapeamento dos endpoints usando o Descriptor 0x2901 (User Description)
    // O ESP-IDF nomeia as características como 'prov-session', 'prov-config', etc.
    List<BluetoothService> services = await device.discoverServices();
    _endpoints.clear();
    
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        for (var desc in characteristic.descriptors) {
          if (desc.characteristicUuid.toString().toUpperCase().contains('2901') || 
              desc.uuid.toString().toUpperCase().contains('2901')) {
            try {
              var value = await desc.read();
              String endpointName = utf8.decode(value).replaceAll('\x00', ''); // Remove null terminator se houver
              if (endpointName.isNotEmpty) {
                _endpoints[endpointName] = characteristic;
                debugPrint('ESP32 Endpoint descoberto: $endpointName na UUID ${characteristic.uuid}');
              }
            } catch (e) {
              debugPrint('Falha ao ler descriptor 2901: $e');
            }
          }
        }
      }
    }
    
    if (_endpoints.isEmpty) {
      debugPrint('Aviso: Nenhum endpoint encontrado via descritores. O firmware expôs os nomes?');
    }
    
    return true;
  }

  @override
  Future<bool> disconnect() async {
    try {
      if (device.isConnected) {
        await device.disconnect();
      }
    } catch (e) {
      debugPrint('Aviso ao desconectar: $e');
    }
    return true;
  }

  @override
  Future<bool> checkConnect() async {
    return device.isConnected;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    var characteristic = _endpoints[epName];
    if (characteristic == null) {
      // Fallback ou erro se não achou via descritor
      throw Exception('Endpoint \$epName não encontrado no dispositivo BLE.');
    }
    
    // No ESP-IDF, o cliente escreve na característica e depois lê da mesma característica.
    try {
      debugPrint('--> Escrevendo em $epName (withoutResponse: false) - ${data.length} bytes');
      await characteristic.write(data.toList(), withoutResponse: false);
    } catch (e) {
      debugPrint('Falha ao escrever em $epName: $e');
      // Pequeno fallback apenas de segurança
      await characteristic.write(data.toList(), withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // Lê a resposta
    debugPrint('<-- Lendo resposta de $epName...');
    var response = await characteristic.read();
    debugPrint('<-- Lida resposta de $epName com ${response.length} bytes');
    return Uint8List.fromList(response);
  }
}
