import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
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
      appBar: AppBar(
        title: Text('Selecione um Dispositivo'),
      ),
      body: StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        initialData: const [],
        builder: (context, snapshot) {
          final results = snapshot.data!;
          if (results.isEmpty) {
            return Center(child: Text('Nenhum dispositivo encontrado.\nCertifique-se que o Bluetooth está ativado.', textAlign: TextAlign.center));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              return ListTile(
                title: Text(result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : 'Dispositivo desconhecido'),
                subtitle: Text(result.device.remoteId.toString()),
                onTap: () {
                  FlutterBluePlus.stopScan();
                  Navigator.pop(context, result.device);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.refresh),
        onPressed: () {
          FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
        },
      ),
    );
  }
}