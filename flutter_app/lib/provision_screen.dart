import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:ssme_esp_provisioning/ssme_esp_provisioning.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_transport.dart';

class ProvisionScreen extends StatefulWidget {
  final BleDevice device;
  
  const ProvisionScreen({Key? key, required this.device}) : super(key: key);

  @override
  _ProvisionScreenState createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  
  bool _isInitializing = true;
  bool _isProvisioning = false;
  bool _isDisconnecting = false;
  bool _isSuccess = false;
  String _statusText = 'Inicializando...';
  bool _obscurePass = true;
  
  EspProv? _prov;
  List<WifiAP> _networks = [];
  String? _selectedSsid;

  @override
  void initState() {
    super.initState();
    _initSessionAndScan();
  }

  String _extractPop() {
    String name = widget.device.name ?? '';
    
    if (name.isEmpty) {
      final macAddress = widget.device.deviceId;
      final parts = macAddress.split(':');
      if (parts.length == 6) {
        // O MAC do Wi-Fi (usado no PoP) costuma ser o MAC do BLE - 2 no ESP32!
        int lastByte = int.parse(parts[5], radix: 16);
        int wifiLastByte = (lastByte - 2) % 256;
        if (wifiLastByte < 0) wifiLastByte += 256;
        String hexWifiLast = wifiLastByte.toRadixString(16).padLeft(2, '0').toUpperCase();
        return '${parts[4]}$hexWifiLast';
      }
    } else {
      if (name.length >= 4) {
        return name.substring(name.length - 4);
      }
    }
    return '';
  }

  void _updateStatus(String msg) {
    if (!mounted) return;
    setState(() {
      _statusText = msg;
    });
  }

  Future<void> _initSessionAndScan() async {
    try {
      final pop = _extractPop();
      debugPrint('Iniciando com PoP: $pop');
      final transport = BleTransport(widget.device);
      final security = Security1(pop: pop);
      
      _prov = EspProv(transport: transport, security: security);
      
      _updateStatus('Conectando e Negociando Sec1...');
      await _prov!.establishSession();
      
      if (defaultTargetPlatform == TargetPlatform.android) {
        _updateStatus('Obtendo rede Wi-Fi atual...');
        debugPrint('Pulando scan Wi-Fi no Android para manter a estabilidade do BLE.');
        
        try {
          // Solicita permissão de localização (necessário no Android para ler o nome do Wi-Fi)
          var status = await Permission.location.request();
          if (status.isGranted) {
            final info = NetworkInfo();
            var wifiName = await info.getWifiName();
            
            if (wifiName != null && wifiName.isNotEmpty) {
              // Remove aspas que o Android adiciona no SSID
              wifiName = wifiName.replaceAll('"', '');
              
              if (mounted) {
                setState(() {
                  _ssidController.text = wifiName!;
                });
              }
            } else {
              debugPrint('Não foi possível obter o SSID. O usuário precisará digitar.');
            }
          } else {
            debugPrint('Permissão de localização negada. O usuário precisará digitar o SSID.');
          }
        } catch (e) {
          debugPrint('Erro ao obter Wi-Fi atual: $e');
        }

      } else {
        _updateStatus('Escaneando redes ao redor do ESP32...');
        try {
          var apList = await _prov!.startScanWiFi();
          
          // Filtrar redes sem nome ou duplicadas
          final uniqueSsids = <String>{};
          for (var ap in apList) {
            if (ap.ssid.isNotEmpty) uniqueSsids.add(ap.ssid);
          }
          
          if (mounted) {
            setState(() {
              _networks = apList.where((ap) => uniqueSsids.remove(ap.ssid)).toList();
              _networks.sort((a, b) => b.rssi.compareTo(a.rssi)); // Mais fortes primeiro
              
              if (_networks.isNotEmpty) {
                _selectedSsid = _networks.first.ssid;
              }
            });
          }
        } catch (scanError) {
          debugPrint('Aviso: O scan Wi-Fi falhou ou não é suportado pelo dispositivo: $scanError');
        }
      }
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Erro na inicialização: $e');
      _updateStatus('Falha na conexão inicial: $e');
    }
  }

  Future<void> _startProvisioning() async {
    final ssid = _networks.isNotEmpty ? _selectedSsid : _ssidController.text;
    final password = _passController.text;
    
    if (ssid == null || ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, informe ou selecione uma rede SSID.')));
      return;
    }

    setState(() {
      _isProvisioning = true;
      _statusText = 'Enviando credenciais...';
    });

    try {
      bool configSent = await _prov!.sendWifiConfig(ssid: ssid, password: password);
      if (!configSent) {
        throw Exception('O ESP32 rejeitou as credenciais');
      }
      
      _updateStatus('Aplicando configurações...');
      bool applied = await _prov!.applyWifiConfig();
      if (!applied) {
        throw Exception('Falha ao aplicar o Wi-Fi');
      }

      _updateStatus('Aguardando ESP32 conectar...');
      await Future.delayed(const Duration(seconds: 3));
      
      try {
        var status = await _prov!.getStatus();
        if (status?.state == WifiConnectionState.Connected) {
          _updateStatus('Sucesso! IP: ${status?.ip}');
        } else {
          _updateStatus('Comando aceito. Verifique o LED.');
        }
      } catch (_) {
        _updateStatus('Conexão BLE finalizada. Verifique o LED.');
      }

      if (mounted) {
        setState(() {
          _isSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProvisioning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _prov?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_isDisconnecting) return; // Evita duplo clique no voltar
        
        setState(() {
          _isDisconnecting = true;
        });
        
        await _prov?.dispose();
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Provisionamento Wi-Fi'),
      ),
      body: _isDisconnecting 
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Desconectando com segurança...', style: TextStyle(fontSize: 16)),
              ],
            ),
          )
        : Padding(
        padding: const EdgeInsets.all(24.0),
        child: _isSuccess
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 100),
                  const SizedBox(height: 24),
                  Text('Dispositivo Conectado!', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  const Text('O ESP32 foi provisionado com sucesso na rede Wi-Fi.', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Voltar para a Busca'),
                  )
                ],
              ),
            )
          : _isInitializing 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(_statusText, textAlign: TextAlign.center),
                ],
              ),
            )
          : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configurar ESP32',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Dispositivo: ${widget.device.deviceId}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_networks.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedSsid,
                decoration: const InputDecoration(
                  labelText: 'Selecione a Rede (SSID)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                items: _networks.map((ap) {
                  return DropdownMenuItem(
                    value: ap.ssid,
                    child: Text('${ap.ssid} (${ap.rssi} dBm)'),
                  );
                }).toList(),
                onChanged: _isProvisioning ? null : (val) {
                  setState(() => _selectedSsid = val);
                },
              )
            else
              TextFormField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'Nome da Rede (SSID)',
                  hintText: 'Digite o nome da sua rede Wi-Fi',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                enabled: !_isProvisioning,
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passController,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Senha da Rede',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _obscurePass = !_obscurePass;
                    });
                  },
                ),
              ),
              enabled: !_isProvisioning,
            ),
            const SizedBox(height: 32),
            if (_isProvisioning) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ] else
              ElevatedButton.icon(
                onPressed: _isProvisioning ? null : _startProvisioning,
                icon: const Icon(Icons.send),
                label: const Text('Provisionar e Conectar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    ));
  }
}
