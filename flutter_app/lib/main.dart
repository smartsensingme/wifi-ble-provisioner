import 'dart:async';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'provision_screen.dart';
import 'config.dart';

void main() {
  // Garantir bindings para o Linux Desktop
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Provisioner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ScanScreen(),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = false;
  List<BleDevice> _scanResults = [];
  final Set<String> _provisionedDevices = {};

  @override
  void initState() {
    super.initState();
    // Escuta continuamente a lista de resultados descobertos pelo adaptador
    UniversalBle.onScanResult = (result) {
      if (mounted) {
        setState(() {
          // Ocultar dispositivos que acabaram de ser provisionados com sucesso
          if (_provisionedDevices.contains(result.deviceId)) {
            return;
          }

          // Fallback por MAC (Útil para debugar no Linux quando o BlueZ "trava" o nome e os UUIDs)
          bool isTarget = false;
          String name = result.name ?? '';
          
          if (name.toUpperCase().contains('PROV')) {
            isTarget = true;
          } else if (result.deviceId.toUpperCase().startsWith('3C:DC:75')) {
            isTarget = true;
          } else if (result.services != null) {
            for (var uuid in result.services!) {
              if (uuid.toString().toLowerCase() == AppConfig.bleProvisioningUuid.toLowerCase()) {
                isTarget = true;
                break;
              }
            }
          }
          
          if (isTarget) {
            final index = _scanResults.indexWhere((r) => r.deviceId == result.deviceId);
            if (index >= 0) {
              _scanResults[index] = result;
            } else {
              _scanResults.add(result);
            }
          }
        });
      }
    };
  }

  @override
  void dispose() {
    UniversalBle.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // No Android 12+, precisamos solicitar explicitly essas permissões antes de escanear
        Map<Permission, PermissionStatus> statuses = await [
          Permission.location,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        
        bool allGranted = true;
        statuses.forEach((key, value) {
          if (!value.isGranted) allGranted = false;
        });
        
        if (!allGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissões de Localização e Bluetooth são obrigatórias no Android.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      setState(() {
        _isScanning = true;
        _scanResults.clear();
      });

      // Em sistemas operacionais desktop é boa prática parar scanners pendentes
      UniversalBle.stopScan();

      // Inicia a busca
      UniversalBle.startScan();

      // Trava visualmente o botão durante o timeout
      await Future.delayed(const Duration(seconds: 15));
      UniversalBle.stopScan();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao escanear dispositivos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan BLE Provisionamento', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
      ),
      body: _scanResults.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'Nenhum ESP32 aguardando provisionamento encontrado.\n\nClique em "Escanear" e certifique-se que o LED do seu firmware está piscando.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          : ListView.separated(
              itemCount: _scanResults.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = _scanResults[index];
                String deviceName = device.name ?? '';
                
                final macAddress = device.deviceId;
                final rssi = device.rssi;

                // Tratamento cosmético para o BlueZ
                if (deviceName.isEmpty) {
                  final macUpper = macAddress.toUpperCase();
                  if (macUpper.startsWith('3C:DC:75') || 
                      macUpper.startsWith('24:6F:28') || 
                      macUpper.startsWith('24:0A:C4')) {
                    deviceName = 'ESP32 Provisioner (Oculto pelo Linux)';
                  } else {
                    deviceName = 'Dispositivo Desconhecido';
                  }
                }

                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.bluetooth_audio),
                  ),
                  title: Text(
                    deviceName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('MAC: $macAddress\nSinal (RSSI): $rssi dBm'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    UniversalBle.stopScan();
                    if (!mounted) return;
                    setState(() {
                      _isScanning = false;
                    });
                    
                    final success = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProvisionScreen(
                          device: device,
                        ),
                      ),
                    );
                    
                    // Se a tela retornar true, significa que provisionou com sucesso
                    if (success == true) {
                      setState(() {
                        _provisionedDevices.add(macAddress);
                        // Remove imediatamente da lista visível
                        _scanResults.removeWhere((r) => r.deviceId == macAddress);
                      });
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _startScan,
        icon: _isScanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.search),
        label: Text(_isScanning ? 'Buscando...' : 'Escanear'),
      ),
    );
  }
}
