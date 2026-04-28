import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  List<ScanResult> _scanResults = [];
  final Set<String> _provisionedDevices = {};
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;

  @override
  void initState() {
    super.initState();
    // Escuta continuamente a lista de resultados descobertos pelo adaptador
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Deduplicar resultados por MAC (Linux BlueZ às vezes duplica eventos de scan)
          final Map<String, ScanResult> uniqueResults = {};
          for (var r in results) {
            uniqueResults[r.device.remoteId.toString()] = r;
          }

          _scanResults = uniqueResults.values.where((r) {
            final name = r.device.advName.isNotEmpty 
                ? r.device.advName 
                : r.advertisementData.advName;
            
            // LOGS DE DEBUG REINSERIDOS
            debugPrint('--- [BLE DETECTADO] MAC: ${r.device.remoteId} ---');
            debugPrint('Nome: "$name"');
            debugPrint('Service UUIDs: ${r.advertisementData.serviceUuids}');
            debugPrint('Manufacturer Data: ${r.advertisementData.manufacturerData}');

            // 1. Ocultar dispositivos que acabaram de ser provisionados com sucesso
            if (_provisionedDevices.contains(r.device.remoteId.toString())) {
              return false;
            }

            if (name.toUpperCase().contains('PROV')) {
              return true;
            }

            // Filtro Definitivo para Linux (e outras plataformas):
            // O serviço de provisionamento.
            for (var uuid in r.advertisementData.serviceUuids) {
              if (uuid.toString().toLowerCase() == AppConfig.bleProvisioningUuid.toLowerCase()) {
                return true;
              }
            }
            
            // Fallback por MAC (Útil para debugar no Linux quando o BlueZ "trava" o nome e os UUIDs)
            if (r.device.remoteId.toString().toUpperCase().startsWith('3C:DC:75')) {
              debugPrint('Achamos pelo MAC ${r.device.remoteId}, ignorando falta de UUID/Nome devido ao BlueZ!');
              return true;
            }

            return false;
          }).toList();
        });
      }
    }, onError: (e) {
      debugPrint('Scan Subscription Error: $e');
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
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
      
      // Validar estado do BlueZ / Bluetooth do S.O.
      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.off) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O Bluetooth (BlueZ) está desligado. Ative-o nas configurações do sistema.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else if (state == BluetoothAdapterState.unauthorized) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissão Bluetooth não concedida.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isScanning = true;
        _scanResults.clear();
      });

      // Em sistemas operacionais desktop é boa prática parar scanners pendentes
      await FlutterBluePlus.stopScan();

      // Inicia a busca limitando o timeout e forçando o filtro no nível do adaptador
      await FlutterBluePlus.startScan(
        withServices: [Guid(AppConfig.bleProvisioningUuid)], // Filtro nativo configurável
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      // Trava visualmente o botão durante o timeout (usando o mesmo tempo)
      await Future.delayed(const Duration(seconds: 15));

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
                final result = _scanResults[index];
                String deviceName = result.device.advName.isNotEmpty 
                    ? result.device.advName 
                    : result.advertisementData.advName;
                
                final macAddress = result.device.remoteId.toString();
                final rssi = result.rssi;

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
                    FlutterBluePlus.stopScan();
                    final success = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProvisionScreen(
                          device: result.device,
                          advData: result.advertisementData,
                        ),
                      ),
                    );
                    
                    // Se a tela retornar true, significa que provisionou com sucesso
                    if (success == true) {
                      setState(() {
                        _provisionedDevices.add(macAddress);
                        // Remove imediatamente da lista visível
                        _scanResults.removeWhere((r) => r.device.remoteId.toString() == macAddress);
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
