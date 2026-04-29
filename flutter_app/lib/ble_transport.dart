import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:ssme_esp_provisioning/ssme_esp_provisioning.dart';
import 'config.dart';

class BleEndpoint {
  final String serviceUuid;
  final String characteristicUuid;
  BleEndpoint(this.serviceUuid, this.characteristicUuid);
}

class BleTransport implements ProvTransport {
  final BleDevice device;
  bool _isConnected = false;
  
  // Mapeamento do nome do endpoint para a característica
  final Map<String, BleEndpoint> _endpoints = {};

  BleTransport(this.device);

  @override
  Future<bool> connect() async {
    try {
      debugPrint('Conectando ao dispositivo ${device.deviceId}...');
      // O universal_ble trata a conexão como um Future. Se não lançar exceção, conectou!
      await UniversalBle.connect(device.deviceId, timeout: const Duration(seconds: 15));
      _isConnected = true;
      
      try {
         await UniversalBle.requestMtu(device.deviceId, 256);
         debugPrint('MTU de 256 bytes requisitado com sucesso.');
      } catch (e) {
         debugPrint('Aviso ao requisitar MTU (pode não ser suportado na plataforma): $e');
      }
      
      debugPrint('Descobrindo serviços de ${device.deviceId}...');
      var services = await UniversalBle.discoverServices(device.deviceId);
      
      _endpoints.clear();
      
      // Função auxiliar para construir o UUID da característica substituindo os bytes 2 e 3 do UUID base
      String buildCharUuid(String baseUuid, String hex16) {
        String cleanBase = baseUuid.toLowerCase();
        if (cleanBase.length == 36) {
          return cleanBase.substring(0, 4) + hex16.toLowerCase() + cleanBase.substring(8);
        } else if (cleanBase.length == 32) {
          return cleanBase.substring(0, 4) + hex16.toLowerCase() + cleanBase.substring(8);
        }
        return "";
      }

      for (var service in services) {
        // Focamos apenas no serviço de provisionamento
        if (service.uuid.toLowerCase() == AppConfig.bleProvisioningUuid.toLowerCase() || 
            service.uuid.toLowerCase() == AppConfig.bleProvisioningUuid.replaceAll('-', '').toLowerCase()) {
          
          // O UniversalBle 1.2.0 não expõe leitura de descritores no Linux.
          // Sabemos que o ESP-IDF (network_provisioning) aloca os endpoints 
          // injetando um ID de 16-bits nos bytes 2 e 3 do UUID do Serviço Base:
          String expectedCtrl = buildCharUuid(AppConfig.bleProvisioningUuid, 'ff4f');
          String expectedScan = buildCharUuid(AppConfig.bleProvisioningUuid, 'ff50');
          String expectedSession = buildCharUuid(AppConfig.bleProvisioningUuid, 'ff51');
          String expectedConfig = buildCharUuid(AppConfig.bleProvisioningUuid, 'ff52');
          String expectedProtoVer = buildCharUuid(AppConfig.bleProvisioningUuid, 'ff53');
          
          for (var charObj in service.characteristics) {
             String endpointName = "";
             String uuidLower = charObj.uuid.toLowerCase();
             String uuidLowerNoDashes = uuidLower.replaceAll('-', '');
             
             if (uuidLower == expectedCtrl || uuidLowerNoDashes == expectedCtrl.replaceAll('-', '')) endpointName = "prov-ctrl";
             else if (uuidLower == expectedScan || uuidLowerNoDashes == expectedScan.replaceAll('-', '')) endpointName = "prov-scan";
             else if (uuidLower == expectedSession || uuidLowerNoDashes == expectedSession.replaceAll('-', '')) endpointName = "prov-session";
             else if (uuidLower == expectedConfig || uuidLowerNoDashes == expectedConfig.replaceAll('-', '')) endpointName = "prov-config";
             else if (uuidLower == expectedProtoVer || uuidLowerNoDashes == expectedProtoVer.replaceAll('-', '')) endpointName = "proto-ver";
             
             if (endpointName.isNotEmpty) {
               _endpoints[endpointName] = BleEndpoint(service.uuid, charObj.uuid);
               debugPrint('ESP32 Endpoint $endpointName mapeado exatamente para UUID ${charObj.uuid}');
             }
          }
        }
      }
      
      if (_endpoints.isEmpty) {
        debugPrint('Aviso: Nenhum endpoint correspondente encontrado no serviço.');
      }
      
      return true;
    } catch (e) {
      debugPrint('Falha ao conectar ou descobrir serviços: $e');
      _isConnected = false;
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      await UniversalBle.disconnect(device.deviceId);
      _isConnected = false;
      return true;
    } catch (e) {
      debugPrint('Aviso ao desconectar: $e');
      return false;
    }
  }

  @override
  Future<bool> checkConnect() async {
    return _isConnected;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    var ep = _endpoints[epName];
    if (ep == null) {
      throw Exception('Endpoint $epName não encontrado no dispositivo BLE.');
    }

    try {
      debugPrint('--> Escrevendo em $epName - ${data.length} bytes');
      await UniversalBle.write(
        device.deviceId, 
        ep.serviceUuid, 
        ep.characteristicUuid, 
        data, 
        withoutResponse: false
      );
    } catch (e) {
      debugPrint('Falha ao escrever em $epName (withResponse): $e');
      // Pequeno fallback apenas de segurança
      await UniversalBle.write(
        device.deviceId, 
        ep.serviceUuid, 
        ep.characteristicUuid, 
        data, 
        withoutResponse: true
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('<-- Lendo resposta de $epName...');
    var response = await UniversalBle.read(device.deviceId, ep.serviceUuid, ep.characteristicUuid);
    debugPrint('<-- Lida resposta de $epName com ${response.length} bytes');
    return response;
  }
}
