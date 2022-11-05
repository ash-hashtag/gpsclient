import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';
import 'package:torch_light/torch_light.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// @pragma('vm:entry-point')
// Future<bool> backgroundService(ServiceInstance instance) async {
//   DartPluginRegistrant.ensureInitialized();
//   try {
//     WidgetsFlutterBinding.ensureInitialized();
//   } catch (_) {}
//   Timer.periodic(const Duration(seconds: 1), (timer) {
//     Location().getLocation().then((locationData) {
//       final payload = [
//         locationData.latitude,
//         locationData.longitude,
//         locationData.altitude
//       ].join(',');
//       print("sending stuff $payload");
//       get(Uri.parse("http://192.168.0.167/ash-hash:$payload}"));
//     });
//   });
//   return true;
// }

// void initWorkManager() {
//   Workmanager().initialize(backgroundService);
// }

// @pragma('vm:entry-point')
// void callBackDispatcher() {
//   Workmanager().executeTask((taskName, inputData) {
//     return get(Uri.parse("http://192.168.0.127/${Random().nextInt(10000)}"))
//         .then((response) => true)
//         .catchError((e) => false);
//   });
// }

// void initBackgroundSerivce() async {
//   final service = FlutterBackgroundService();

//   await service.configure(
//       iosConfiguration: IosConfiguration(
//         onForeground: backgroundService,
//         onBackground: backgroundService,
//       ),
//       androidConfiguration: AndroidConfiguration(
//           autoStart: true,
//           autoStartOnBoot: true,
//           onStart: backgroundService,
//           isForegroundMode: false));
//   await service.startService();

//   print("started service");
// }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final addressTc = TextEditingController();
  final idTc = TextEditingController();
  final intervalTc = TextEditingController();
  final passwordTc = TextEditingController();

  final appDirectoryPath =
      getApplicationDocumentsDirectory().then((value) => value.path);

  bool get currentlyInActive => subscription == null;
  int get interval {
    var val = int.tryParse(intervalTc.text) ?? 1000;
    intervalTc.text = val.toString();
    return val;
  }

  StreamSubscription? subscription, socketSubscription;
  WebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    getPermissions().then((_) => getStoredVariables());
  }

  Future getPermissions() async {
    final location = Location();
    const limit = 10;
    for (int i = 0; i < limit; i++) {
      try {
        final result = await location.serviceEnabled();
        print("service is $result");
        if (result) {
          break;
        } else {
          await location.requestService();
        }
      } on PlatformException {
        print("thrown error location requested");
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    for (var i = 0; i < limit; i++) {
      if (await location.hasPermission() == PermissionStatus.granted) {
        break;
      } else {
        print("requesting permission");
        await location.requestPermission();
      }
    }
  }

  @override
  void dispose() {
    idTc.dispose();
    addressTc.dispose();
    intervalTc.dispose();
    passwordTc.dispose();
    super.dispose();
  }

  void getStoredVariables() async {
    final file = File("${await appDirectoryPath}/prefs");
    if (file.existsSync()) {
      final fileString = file.readAsStringSync();
      final Map<String, dynamic> map = jsonDecode(fileString);
      if (map.isNotEmpty) {
        setState(() {
          idTc.text = map["id"] ?? "";
          addressTc.text = map["addr"] ?? "";
          intervalTc.text = (map["interval"] ?? 1000).toString();
        });

        if (map["running"] ?? false) {
          start();
        }
      }
    }
  }

  void showSnackBar(String text) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void start() async {
    if (addressTc.text.isEmpty ||
        idTc.text.isEmpty ||
        intervalTc.text.isEmpty) {
      showSnackBar("Some Field/s are missing");
      return;
    }
    final location = Location();

    for (var i = 0; i < 10; i++) {
      if (!await location.isBackgroundModeEnabled()) {
        await location.enableBackgroundMode(enable: true);
      } else {
        break;
      }
    }
    await location.changeSettings(interval: interval);
    setState(() {
      subscription = location.onLocationChanged.listen(sendLocationData);
    });
    print(
        "connecting to socket ${addressTc.text} interval: ${intervalTc.text}");
    connectToSocket();

    updateData(true);
    // turnOnTorchLight();
  }

  void onSocketClosed() {
    socketSubscription?.cancel();
    socketSubscription = null;

    channel?.sink.close();
    channel = null;

    turnOffTorchLight();
  }

  void connectToSocket() {
    if (channel != null) {
      channel!.sink.close();
      channel = null;
    }
    channel = WebSocketChannel.connect(Uri.parse(addressTc.text));

    socketSubscription = channel!.stream.listen((_) {},
        onDone: onSocketClosed, onError: (_) => onSocketClosed());

    turnOnTorchLight();
  }

  void stop() {
    // socketSubscription?.cancel();
    // socketSubscription = null;

    // channel?.sink.close();
    // channel = null;

    onSocketClosed();

    setState(() {
      subscription?.cancel();
      subscription = null;
    });
    // serverType = ServerType.none;

    updateData(false);
    Location().enableBackgroundMode(enable: false);
  }

  void updateData(bool running) async {
    if (idTc.text.isNotEmpty && addressTc.text.isNotEmpty) {
      final file = File("${await appDirectoryPath}/prefs");
      file.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({
        "id": idTc.text,
        "addr": addressTc.text,
        "interval": interval,
        "running": running
      }));
      print("Updated Data Locally");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Where you at?")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text("status: ${currentlyInActive ? 'offline' : 'online'}"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              controller: idTc,
              enabled: currentlyInActive,
              decoration: const InputDecoration(
                  hintText: "user00123", label: Text("Id")),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              controller: addressTc,
              enabled: currentlyInActive,
              decoration: const InputDecoration(
                  label: Text("Address"),
                  hintText: "http://127.0.0.1:8080 or ws://192.168.0.123"),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              controller: intervalTc,
              enabled: currentlyInActive,
              decoration: const InputDecoration(
                  label: Text("Interval in ms"), hintText: "1000"),
            ),
          ),
          TextButton(
              onPressed: currentlyInActive ? start : stop,
              child: Text(currentlyInActive ? "Start" : "Stop")),
        ],
      ),
    );
  }

  Future sendLocationData(LocationData locationData) async {
    if (idTc.text.isNotEmpty && addressTc.text.isNotEmpty) {
      final idxyz = [
        DateTime.now().toIso8601String(),
        idTc.text,
        locationData.accuracy ?? 0,
        locationData.satelliteNumber ?? -1,
        locationData.latitude,
        locationData.longitude,
        locationData.altitude,
      ].join(',');
      if (channel != null) {
        if (channel!.closeCode == null) {
          channel!.sink.add(idxyz);
          blinkOffTorchLight();
        }
      } else {
        connectToSocket();
      }
    }
  }

  void blinkOffTorchLight() {
    turnOffTorchLight();
    Future.delayed(const Duration(milliseconds: 100), turnOnTorchLight);
  }

  void turnOnTorchLight() {
    TorchLight.isTorchAvailable()
        .then((value) => value ? TorchLight.enableTorch() : null)
        .catchError((_) {});
  }

  void turnOffTorchLight() {
    TorchLight.disableTorch().catchError((_) {});
  }
}

// class DropDownMenuServerType extends StatefulWidget {
//   final void Function(ServerType) onChanged;
//   final ServerType value;

//   final bool isEnabled;

//   const DropDownMenuServerType({
//     super.key,
//     required this.onChanged,
//     required this.value,
//     required this.isEnabled,
//   });

//   @override
//   State<DropDownMenuServerType> createState() => _DropDownMenuServerTypeState();
// }

// class _DropDownMenuServerTypeState extends State<DropDownMenuServerType> {
//   final items = <DropdownMenuItem<ServerType>>[
//     const DropdownMenuItem(value: ServerType.none, child: Text("none")),
//     const DropdownMenuItem(value: ServerType.http, child: Text("http")),
//     const DropdownMenuItem(value: ServerType.socket, child: Text("socket")),
//   ];

//   late var value = items[0].value;
//   @override
//   Widget build(BuildContext context) {
//     return DropdownButton(
//       value: value,
//       items: items,
//       onChanged: (val) => widget.isEnabled
//           ? setState(
//               () {
//                 if (val != null) {
//                   value = val;
//                   widget.onChanged(val);
//                 }
//               },
//             )
//           : null,
//     );
//   }
// }
