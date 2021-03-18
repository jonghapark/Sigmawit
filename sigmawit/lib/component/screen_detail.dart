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
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_charts/sparkcharts.dart';

class DetailScreen extends StatefulWidget {
  final BleDeviceItem currentDevice;
  final Uint8List minmaxStamp;

  DetailScreen({this.currentDevice, this.minmaxStamp});

  @override
  _DetailScreenState createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  StreamSubscription monitoringStreamSubscription;
  bool dataFetchEnd = false;
  List<LogData> fetchDatas = [];

  @override
  void initState() {
    super.initState();
    fetchLogData();
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

  fetchLogData() async {
    await monitorCharacteristic(widget.currentDevice.peripheral);
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
          fetchDatas.add(transformData(notifyResult));
        }
        // DataFetch End
        else if (notifyResult[10] == 0x06) {
          setState(() {
            dataFetchEnd = true;
          });
        }
      },
      onError: (error) {
        print("Error while monitoring characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  //Datalog Parsing
  LogData transformData(Uint8List notifyResult) {
    print('온도 : ' + getLogTemperature(notifyResult).toString());
    print('습도 : ' + getLogHumidity(notifyResult).toString());
    print('시간 : ' + getLogTime(notifyResult).toString());
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
          characteristic.monitor(transactionId: "monitor2"), peripheral);
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
                dataFetchEnd == false
                    ? CircularProgressIndicator()
                    : Container(
                        child: Column(
                        children: [
                          SfCartesianChart(
                              primaryXAxis: CategoryAxis(),
                              // Chart title
                              title: ChartTitle(text: '온도/습도 그래프'),
                              // Enable legend
                              legend: Legend(isVisible: false),
                              // Enable tooltip
                              tooltipBehavior: TooltipBehavior(enable: true),
                              series: <ChartSeries<LogData, String>>[
                                LineSeries<LogData, String>(
                                    dataSource: fetchDatas.sublist(0, 30),
                                    xValueMapper: (LogData data, _) =>
                                        data.timestamp.toString(),
                                    yValueMapper: (LogData data, _) =>
                                        data.temperature,
                                    name: '온도',
                                    // Enable data label
                                    dataLabelSettings:
                                        DataLabelSettings(isVisible: true))
                              ]),
                          // Padding(
                          //   padding: const EdgeInsets.all(8.0),
                          //   //Initialize the spark charts widget
                          //   child: SfSparkLineChart.custom(
                          //     //Enable the trackball
                          //     trackball: SparkChartTrackball(
                          //         activationMode: SparkChartActivationMode.tap),
                          //     //Enable marker
                          //     marker: SparkChartMarker(
                          //         displayMode: SparkChartMarkerDisplayMode.all),
                          //     //Enable data label
                          //     labelDisplayMode: SparkChartLabelDisplayMode.all,
                          //     xValueMapper: (int index) =>
                          //         fetchDatas[index].timestamp,
                          //     yValueMapper: (int index) =>
                          //         fetchDatas[index].temperature,
                          //     dataCount: 5,
                          //   ),
                          // )
                        ],
                      ))
              ],
            ))));
  }
}
