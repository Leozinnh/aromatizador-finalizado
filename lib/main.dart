import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Configurar Aromatizador',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;
  bool isConnected = false;

  // Configurações
  final serviceUUID = "4c656f6e-6172-646f-416c-766573000000";
  final rxUUID = "4c656f6e-6172-646f-416c-766573000001";
  final txUUID = "4c656f6e-6172-646f-416c-766573000002";

  // Controles de formulário
  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 15, minute: 0);
  int interval = 300; // 5 minutos em segundos
  int sprayDuration = 15; // segundos
  List<bool> weekDays = List.generate(7, (index) => true);

  final List<String> diasSemana = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
  ];

  // Novo método para selecionar dispositivo
  Future<void> selectDevice() async {
    await disconnectDevice(); // <- sempre desconecta antes
    final BluetoothDevice? selectedDevice = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DevicesScreen()),
    );
    if (selectedDevice != null) {
      await connectToDevice(selectedDevice);
    }
  }

  Future<void> initBluetooth() async {
    // Verifica permissões primeiro
    if (!await FlutterBluePlus.isSupported) {
      print("Bluetooth não suportado");
      return;
    }

    // Inicia scan
    try {
      await FlutterBluePlus.turnOn();

      // Aguarda o adaptador estar pronto
      await FlutterBluePlus.adapterState.first;

      // Solicita permissões
      await pedirPermissoesBluetooth(context);

      // Inicia o scan
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 4),
        androidUsesFineLocation: true,
      );

      // Escuta resultados
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == 'HomeLoft') {
            FlutterBluePlus.stopScan();
            connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      print('Erro ao iniciar scan: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice d) async {
    if (device != null) return;

    setState(() => device = d);
    await device?.connect();

    // Descobre serviços
    List<BluetoothService> services = await device!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == serviceUUID) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == txUUID) {
            txCharacteristic = characteristic;
          }
          if (characteristic.uuid.toString() == rxUUID) {
            rxCharacteristic = characteristic;
          }
        }
      }
    }

    setState(() => isConnected = true);
  }

  Future<void> sendConfig() async {
    if (!isConnected || rxCharacteristic == null) {
      print('Não conectado ou characteristic não encontrada');
      return;
    }

    // Calcula bitmask dos dias da semana
    int daysMask = 0;
    for (int i = 0; i < 7; i++) {
      if (weekDays[i]) daysMask |= (1 << i);
    }

    String config =
        'GET /4,$daysMask,$interval,$sprayDuration,${startTime.hour},${startTime.minute},${endTime.hour},${endTime.minute},${startTime.hour},${startTime.minute},${endTime.hour},${endTime.minute},';

    print('Enviando: $config');

    try {
      // Primeiro sincroniza o horário
      await sendCurrentTime();

      // Depois envia a configuração
      await rxCharacteristic!.write(
        utf8.encode(config),
        withoutResponse: false,
      );
      print('Configuração enviada via BLE!');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configuração enviada com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Erro ao enviar configuração: $e');
      setState(() => isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bluetooth desconectado! Conecte novamente ao dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> sendCurrentTime() async {
    if (!isConnected || rxCharacteristic == null) {
      print('Não conectado ou characteristic não encontrada');
      return;
    }
    int unixTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    String payload = 'UT$unixTime';
    print('Enviando horário: $payload');
    try {
      await rxCharacteristic!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );
      print('Horário enviado via BLE!');
    } catch (e) {
      print('Erro ao enviar horário: $e');
      setState(() => isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bluetooth desconectado! Conecte novamente ao dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Adicione estes métodos para os diálogos
  Future<void> _showIntervalDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        int tempInterval = interval;
        return AlertDialog(
          title: Text('Intervalo entre sprays'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Defina o intervalo em segundos:'),
              TextField(
                controller: TextEditingController(text: interval.toString()),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    tempInterval = int.tryParse(value) ?? interval,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Confirmar'),
              onPressed: () {
                setState(() => interval = tempInterval);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDurationDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        int tempDuration = sprayDuration;
        return AlertDialog(
          title: Text('Duração do spray'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Defina a duração em segundos:'),
              TextField(
                // Substitui initialValue por controller
                controller: TextEditingController(
                  text: sprayDuration.toString(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    tempDuration = int.tryParse(value) ?? sprayDuration,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Confirmar'),
              onPressed: () {
                setState(() => sprayDuration = tempDuration);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> disconnectDevice() async {
    if (device != null) {
      try {
        await device!.disconnect();
      } catch (_) {}
      device = null;
      txCharacteristic = null;
      rxCharacteristic = null;
      setState(() => isConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Configurar Aromatizador',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: Colors.white,
            ),
            onPressed: selectDevice,
          ),
        ],
      ),
      body: Center(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Dias de Funcionamento',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: List.generate(7, (i) {
                        final selected = weekDays[i];
                        return FilterChip(
                          label: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              diasSemana[i],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : Colors.blue.shade900,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          selected: selected,
                          selectedColor: Colors.blue.shade600,
                          backgroundColor: Colors.blue.shade50,
                          checkmarkColor: Colors.white,
                          avatar: selected
                              ? Icon(Icons.check, color: Colors.white, size: 20)
                              : Icon(
                                  Icons.circle_outlined,
                                  color: Colors.blue.shade300,
                                  size: 20,
                                ),
                          elevation: selected ? 6 : 2,
                          pressElevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: selected
                                  ? Colors.blue.shade700
                                  : Colors.blue.shade200,
                              width: 2,
                            ),
                          ),
                          onSelected: (bool value) {
                            setState(() => weekDays[i] = value);
                          },
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      }),
                    ),
                    const SizedBox(height: 32),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Horário Início'),
                            trailing: Text(startTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: startTime,
                              );
                              if (time != null) {
                                setState(() => startTime = time);
                              }
                            },
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Horário Fim'),
                            trailing: Text(endTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: endTime,
                              );
                              if (time != null) setState(() => endTime = time);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Intervalo entre sprays'),
                            trailing: Text('$interval s'),
                            onTap: _showIntervalDialog,
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Duração do spray'),
                            trailing: Text('$sprayDuration s'),
                            onTap: _showDurationDialog,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? sendConfig : null,
                        icon: const Icon(Icons.save),
                        label: const Text('Salvar Configuração'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: isConnected
                              ? Colors.blue
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? sendCurrentTime : null,
                        icon: const Icon(Icons.access_time),
                        label: const Text('Sincronizar Horário'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: isConnected
                              ? Colors.green
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.only(right: 8, bottom: 4),
                child: Text(
                  'Criado por Leonardo Alves',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    FlutterBluePlus.stopScan(); // <-- Garante que não há scan antigo
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Selecione um Dispositivo')),
      body: StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        initialData: const [],
        builder: (context, snapshot) {
          final results = snapshot.data!;
          if (results.isEmpty) {
            return Center(
              child: Text(
                'Nenhum dispositivo encontrado.\nCertifique-se que o Bluetooth está ativado.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();

          return ListView.builder(
            itemCount: filteredResults.length,
            itemBuilder: (context, index) {
              final result = filteredResults[index];
              return ListTile(
                title: Text(result.device.platformName),
                subtitle: Text(result.device.remoteId.toString()),
                onTap: () async {
                  FlutterBluePlus.stopScan();
                  final device = result.device;
                  await device.connect(timeout: Duration(seconds: 10));
                  Navigator.pop(context, device);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.refresh),
        onPressed: () async {
          await pedirPermissoesBluetooth(context);
          FlutterBluePlus.stopScan(); // <-- Adicione esta linha para garantir
          FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
        },
      ),
    );
  }
}

// Coloque isso fora de qualquer classe, no topo do arquivo (após os imports):
Future<void> pedirPermissoesBluetooth(BuildContext context) async {
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();

  Location location = Location();
  bool serviceEnabled = await location.serviceEnabled();
  if (!serviceEnabled) {
    serviceEnabled = await location.requestService();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ative a localização para usar o Bluetooth!')),
        );
      }
      return;
    }
  }
}
