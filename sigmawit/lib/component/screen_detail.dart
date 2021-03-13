import 'package:flutter/material.dart';
import 'package:sigmawit/models/model_bleDevice.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoder/geocoder.dart';
import 'package:intl/intl.dart';
import 'package:sigmawit/models/model_logdata.dart';

class DetailScreen extends StatefulWidget {
  final BleDeviceItem currentDevice;
  final Uint8List minmaxStamp;

  DetailScreen({this.currentDevice, this.minmaxStamp});

  @override
  _DetailScreenState createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  StreamSubscription monitoringStreamSubscription;

  @override
  void initState() {
    super.initState();
  }

  getLogTime(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(12, 16)).getInt32(0, Endian.big);
    // print(tmp);
    DateTime time = DateTime.fromMicrosecondsSinceEpoch(tmp);
    return time;
  }

  getLogHumidity(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(18, 20)).getInt16(0, Endian.big);
    // print(tmp);
    return tmp / 100;
  }

  getLogTemperature(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(16, 18)).getInt16(0, Endian.big);
    // print(tmp);
    return tmp / 100;
  }

  Future<List<LogData>> fetchLogData() async {
    await monitorCharacteristic(widget.currentDevice.peripheral);
    print('끝');
    var writeCharacteristics = await widget.currentDevice.peripheral
        .writeCharacteristic(
            '00001000-0000-1000-8000-00805f9b34fb',
            '00001001-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                widget.currentDevice.getMacAddress() +
                [0x04, 0x06] +
                widget.minmaxStamp),
            true);
  }

  void _startMonitoringTemperature(
      Stream<Uint8List> characteristicUpdates, Peripheral peripheral) async {
    await monitoringStreamSubscription?.cancel();
    monitoringStreamSubscription = characteristicUpdates.listen(
      (notifyResult) async {
        print(notifyResult.toString());

        if (notifyResult[10] == 0x05) {
          //TODO: 데이터 읽어오기

        }
      },
      onError: (error) {
        print("Error while monitoring characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  LogData transformData(Uint8List notifyResult) {
    return new LogData(
        temperature: getLogTemperature(notifyResult),
        humidity: getLogHumidity(notifyResult),
        timestamp: getLogTime(notifyResult));
  }

  Future<void> monitorCharacteristic(Peripheral peripheral) async {
    await _runWithErrorHandling(() async {
      Service service = await peripheral.services().then((services) =>
          services.firstWhere((service) =>
              service.uuid == '00001000-0000-1000-8000-00805f9b34fb'));

      List<Characteristic> characteristics = await service.characteristics();
      Characteristic characteristic = characteristics.firstWhere(
          (characteristic) =>
              characteristic.uuid == '00001002-0000-1000-8000-00805f9b34fb');

      _startMonitoringTemperature(
          characteristic.monitor(transactionId: "monitor"), peripheral);
    });
  }

  //BLE 연결시 예외 처리를 위한 래핑 함수
  _runWithErrorHandling(runFunction) async {
    try {
      await runFunction();
    } on BleError catch (e) {
      print("BleError caught: ${e.errorCode.value} ${e.reason}");
    } catch (e) {
      if (e is Error) {
        debugPrintStack(stackTrace: e.stackTrace);
      }
      print("${e.runtimeType}: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'OPBT',
        theme: ThemeData(
          // primarySwatch: Colors.grey,
          primaryColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
          //canvasColor: Colors.transparent,
        ),
        home: Scaffold(
            appBar: AppBar(
                // backgroundColor: Color.fromARGB(22, 27, 32, 1),
                title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'OPBT',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w300),
                ),
              ],
            )),
            body: Center(
                child: Column(
              children: [
                FutureBuilder(
                    future: fetchLogData(),
                    builder: (BuildContext context, AsyncSnapshot snapshot) {
                      if (snapshot.hasData == false) {
                        return CircularProgressIndicator(
                          semanticsLabel: '데이터 로드 중',
                          semanticsValue: '10%',
                        );
                      } else if (snapshot.hasError) {
                        return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              'Error : ${snapshot.error}',
                              style: TextStyle(fontSize: 15),
                            ));
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            snapshot.data.toString(),
                            style: TextStyle(fontSize: 15),
                          ),
                        );
                      }
                    }),
              ],
            ))));
  }
}
