import 'package:flutter/material.dart';
import 'package:sigmawit/models/model_bleDevice.dart';
import 'package:sigmawit/models/model_logdata.dart';
import 'package:sigmawit/utils/util.dart';

import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'package:geocoder/geocoder.dart';
import 'package:intl/intl.dart';
import 'package:sigmawit/models/model_logdata.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:tab_indicator_styler/tab_indicator_styler.dart';

class DetailScreen extends StatefulWidget {
  final BleDeviceItem currentDevice;
  final Uint8List minmaxStamp;

  DetailScreen({this.currentDevice, this.minmaxStamp});

  @override
  _DetailScreenState createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  StreamSubscription monitoringStreamSubscription;
  StreamSubscription<loc.LocationData> _locationSubscription;
  bool dataFetchEnd = false;
  List<LogData> fetchDatas = [];
  List<LogData> filteredDatas = [];
  int count = 0;

  String log = '데이터 가져오는 중';

  loc.Location location = new loc.Location();
  loc.LocationData currentLocation;
  String geolocation;

  DateTimeIntervalType currentType = DateTimeIntervalType.hours;

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
    fetchLogData();
  }

  getCurrentLocation() async {
    bool _serviceEnabled;
    loc.PermissionStatus _permissionGranted;
    loc.LocationData _locationData;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    _locationData = await location.getLocation();
    print('lat: ' + _locationData.latitude.toString());
    setState(() {
      currentLocation = _locationData;
    });
  }

  Future<void> _listenLocation() async {
    _locationSubscription =
        location.onLocationChanged.handleError((dynamic err) {
      setState(() {
        // _error = err.code;
      });
      _locationSubscription.cancel();
    }).listen((loc.LocationData currentLocation) async {
      final coordinates =
          new Coordinates(currentLocation.latitude, currentLocation.longitude);
      var addresses =
          await Geocoder.local.findAddressesFromCoordinates(coordinates);
      var first = addresses.first;
      // if (!_isScanning) {
      //   scan();
      // }
      if (this.geolocation != first.addressLine) {
        setState(() {
          // _error = null;
          this.currentLocation = currentLocation;
          this.geolocation = first.addressLine;
        });
      }
    });
  }

  sendFetchData() async {
    for (int i = 0; i < filteredDatas.length; i++) {
      Data sendData = new Data(
        battery: widget.currentDevice.getBattery().toString(),
        deviceName:
            'OP_' + widget.currentDevice.getDeviceId().toString().substring(7),
        humi: filteredDatas[i].humidity.toString(),
        temper: filteredDatas[i].temperature.toString(),
        lat: currentLocation.latitude.toString() ?? '',
        lng: currentLocation.longitude.toString() ?? '',
        time: filteredDatas[i].timestamp.toString(),
        lex: '',
      );
      print(widget.currentDevice.getBattery().toString() +
          'OP_' +
          widget.currentDevice.getDeviceId().toString().substring(7) +
          filteredDatas[i].humidity.toString() +
          filteredDatas[i].temperature.toString() +
          currentLocation.latitude.toString() +
          currentLocation.longitude.toString() +
          filteredDatas[i].timestamp.toString());
      await sendtoServer(sendData);
    }
    print('send Data !!');
  }

  Future<Post> sendtoServer(Data data) async {
    var client = http.Client();
    try {
      var uriResponse =
          await client.post('http://175.126.232.236/_API/saveData.php', body: {
        "isRegularData": "true",
        "tra_datetime": data.time,
        "tra_temp": data.temper,
        "tra_humidity": data.humi,
        "tra_lat": data.lat,
        "tra_lon": data.lng,
        "de_number": data.deviceName,
        "tra_battery": data.battery,
      });

      // print(await client.get(uriResponse.body['uri'].toString()));
    } catch (e) {
      print(e);
      return null;
    } finally {
      print('send !');
      client.close();
    }
  }

  dataFiltering(int index) {
    List<LogData> tmp = [];
    if (index == 0) {
      DateTime oneHourAgo = DateTime.now().subtract(Duration(hours: 1));
      for (int i = fetchDatas.length - 1; i > 0; i--) {
        if (fetchDatas[i].timestamp.isAfter(oneHourAgo))
          tmp.add(fetchDatas[i]);
        else
          break;
      }
      print(tmp.length);
      setState(() {
        filteredDatas = tmp;
      });
    } else if (index == 1) {
      DateTime oneDayAgo = DateTime.now().subtract(Duration(days: 1, hours: 1));
      for (int i = fetchDatas.length - 1; i > 0; i--) {
        if (fetchDatas[i].timestamp.isAfter(oneDayAgo))
          tmp.add(fetchDatas[i]);
        else
          break;
      }
      print(tmp.length);
      setState(() {
        filteredDatas = tmp;
      });
    } else if (index == 2) {
      DateTime oneWeekAgo = DateTime.now().subtract(Duration(days: 8));
      for (int i = fetchDatas.length - 1; i > 0; i--) {
        if (fetchDatas[i].timestamp.isAfter(oneWeekAgo))
          tmp.add(fetchDatas[i]);
        else
          break;
      }
      setState(() {
        filteredDatas = tmp;
      });
    } else if (index == 3) {
      DateTime oneMonthAgo = DateTime.now().subtract(Duration(days: 31));
      for (int i = fetchDatas.length - 1; i > 0; i--) {
        if (fetchDatas[i].timestamp.isAfter(oneMonthAgo))
          tmp.add(fetchDatas[i]);
        else
          break;
      }
      setState(() {
        filteredDatas = tmp;
      });
    } else {
      DateTime oneYearAgo = DateTime.now().subtract(Duration(days: 364));
      for (int i = fetchDatas.length - 1; i > 0; i--) {
        if (fetchDatas[i].timestamp.isAfter(oneYearAgo))
          tmp.add(fetchDatas[i]);
        else
          break;
      }
      setState(() {
        filteredDatas = tmp;
      });
    }
  }

  DateTimeIntervalType toggleType(int index) {
    dataFiltering(index);

    if (index == 0)
      return DateTimeIntervalType.minutes;
    else if (index == 1)
      return DateTimeIntervalType.hours;
    else if (index == 2)
      return DateTimeIntervalType.days;
    else if (index == 3)
      return DateTimeIntervalType.auto;
    else
      return DateTimeIntervalType.auto;
  }

  getLogTime(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(12, 16)).getInt32(0, Endian.big);
    DateTime time =
        DateTime.fromMillisecondsSinceEpoch(tmp * 1000, isUtc: true);

    return time;
  }

  getLogHumidity(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(18, 20)).getInt16(0, Endian.big);

    return tmp / 100;
  }

  getLogTemperature(Uint8List fetchData) {
    int tmp =
        ByteData.sublistView(fetchData.sublist(16, 18)).getInt16(0, Endian.big);

    return tmp / 100;
  }

  fetchLogData() async {
    await monitorCharacteristic(widget.currentDevice.peripheral);
    print('Write Start');
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
          if (count % 9 == 0) {
            fetchDatas.add(transformData(notifyResult));
          }
          count++;
        }
        // DataFetch End
        else if (notifyResult[10] == 0x06) {
          print('총 몇개? ' + count.toString());
          print('Read End !');
          List<LogData> tmp = [];
          DateTime oneDayAgo =
              DateTime.now().subtract(Duration(days: 1, hours: 1));
          for (int i = 0; i < fetchDatas.length; i++) {
            if (fetchDatas[i].timestamp.isAfter(oneDayAgo))
              tmp.add(fetchDatas[i]);
          }
          setState(() {
            filteredDatas = tmp;
            dataFetchEnd = true;
          });
        }
      },
      onError: (error) {
        print("Error while monitoring characteristic \n$error");
        if (dataFetchEnd == false) {
          showMyDialog(context);
        }
      },
      cancelOnError: true,
    );
  }

  //Datalog Parsing
  LogData transformData(Uint8List notifyResult) {
    // print('온도 : ' + getLogTemperature(notifyResult).toString());
    // print('습도 : ' + getLogHumidity(notifyResult).toString());
    // print('시간 : ' + getLogTime(notifyResult).toString());
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
        title: 'OPTILO',
        theme: ThemeData(
          // primarySwatch: Colors.grey,
          primaryColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
          //canvasColor: Colors.transparent,
        ),
        home: Scaffold(
            appBar: AppBar(
              // backgroundColor: Color.fromARGB(22, 27, 32, 1),
              title: Row(
                  // mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 9,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'OPTILO',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w300),
                            ),
                          ]),
                    ),
                    Expanded(
                        flex: 7,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              new IconButton(
                                icon: new Icon(Icons.file_upload, size: 25),
                                onPressed: () {
                                  showUploadDialog(
                                      context, filteredDatas.length);
                                  sendFetchData();
                                  // print(
                                  //     filteredDatas[0].temperature.toString());
                                  // print(
                                  //     filteredDatas[1].temperature.toString());
                                },
                              )
                            ])),
                  ]),
            ),
            body: Center(
                child: Column(
              children: [
                DefaultTabController(
                    length: 5,
                    initialIndex: 1,
                    child: Center(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Material(
                                    child: TabBar(
                                      onTap: (index) => {
                                        setState(() {
                                          currentType = toggleType(index);
                                        })
                                      },
                                      indicatorColor: Colors.green,
                                      tabs: [
                                        Tab(
                                          text: "Hour",
                                        ),
                                        Tab(
                                          text: "Day",
                                        ),
                                        Tab(
                                          text: "Week",
                                        ),
                                        Tab(
                                          text: "Month",
                                        ),
                                        Tab(
                                          text: "Year",
                                        ),
                                      ],
                                      labelColor: Colors.black,
                                      indicator: MaterialIndicator(
                                        height: 5,
                                        topLeftRadius: 8,
                                        topRightRadius: 8,
                                        horizontalPadding: 5,
                                        tabPosition: TabPosition.bottom,
                                      ),
                                    ),
                                  )
                                ])))),
                Text(''),
                dataFetchEnd == true
                    ? Text(filteredDatas[filteredDatas.length - 1]
                            .timestamp
                            .toString()
                            .substring(0, 19) +
                        ' ~ ' +
                        filteredDatas[0].timestamp.toString().substring(0, 19))
                    : Text(''),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    dataFetchEnd == false
                        ? Container(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    log,
                                    style: thinTextStyle,
                                  ),
                                  Text(''),
                                  log == '데이터 가져오는 중'
                                      ? CircularProgressIndicator(
                                          backgroundColor: Colors.black26,
                                        )
                                      : SizedBox(),
                                ]))
                        : Container(
                            height: MediaQuery.of(context).size.height * 0.75,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                SfCartesianChart(
                                    primaryXAxis: DateTimeAxis(
                                        labelRotation: 5,
                                        maximumLabels: 5,
                                        // Set name for x axis in order to use it in the callback event.
                                        name: 'primaryXAxis',
                                        intervalType: currentType,
                                        majorGridLines:
                                            MajorGridLines(width: 1)),
                                    // primaryYAxis:
                                    //     NumericAxis(interval: 1, maximum: 30),
                                    // Chart title
                                    title: ChartTitle(text: '온도 그래프'),
                                    // Enable legend
                                    legend: Legend(isVisible: false),
                                    // Enable tooltip
                                    tooltipBehavior:
                                        TooltipBehavior(enable: true),
                                    series: <ChartSeries<LogData, DateTime>>[
                                      LineSeries<LogData, DateTime>(
                                          dataSource: filteredDatas,
                                          xValueMapper: (LogData data, _) {
                                            return data.timestamp;
                                          },
                                          yValueMapper: (LogData data, _) =>
                                              data.temperature,
                                          name: '온도',
                                          // Enable data label
                                          dataLabelSettings: DataLabelSettings(
                                              isVisible: false))
                                    ]),
                                SfCartesianChart(
                                    primaryXAxis: DateTimeAxis(
                                        labelRotation: 5,
                                        maximumLabels: 5,
                                        // Set name for x axis in order to use it in the callback event.
                                        name: 'primaryXAxis',
                                        intervalType: currentType,
                                        majorGridLines:
                                            MajorGridLines(width: 0.5)),
                                    // Chart title
                                    title: ChartTitle(text: '습도 그래프'),
                                    // Enable legend
                                    legend: Legend(isVisible: false),
                                    // Enable tooltip
                                    tooltipBehavior:
                                        TooltipBehavior(enable: true),
                                    series: <ChartSeries<LogData, DateTime>>[
                                      LineSeries<LogData, DateTime>(
                                          dataSource: filteredDatas,
                                          xValueMapper: (LogData data, _) {
                                            return data.timestamp;
                                          },
                                          yValueMapper: (LogData data, _) =>
                                              data.humidity,
                                          name: '습도',
                                          // Enable data label
                                          dataLabelSettings: DataLabelSettings(
                                              isVisible: false))
                                    ]),
                              ],
                            ))
                  ],
                )
              ],
            ))));
  }
}

TextStyle thinTextStyle = TextStyle(
  fontSize: 20,
  color: Color.fromRGBO(20, 20, 20, 1),
  fontWeight: FontWeight.w200,
);

showMyDialog(BuildContext context) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Color.fromRGBO(22, 33, 55, 1),
        elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 4,
            padding: EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text("로드 중 에러가 발생",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}

showUploadDialog(BuildContext context, int size) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Color.fromRGBO(22, 33, 55, 1),
        elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 4,
            padding: EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text('총 ' + size.toString() + '개의 데이터를 전송합니다.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                              fontSize: 14),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}
