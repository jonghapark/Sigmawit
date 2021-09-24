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

import 'package:downloads_path_provider/downloads_path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:esys_flutter_share/esys_flutter_share.dart';

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
  ScreenshotController screenshotController = ScreenshotController();
  Uint8List _imageFile;
  pw.Document pdf = pw.Document();

  bool dataFetchEnd = false;
  List<LogData> fetchDatas = [];
  List<LogData> filteredDatas = [];
  int count = 0;
  int unConditionalCount = 0;
  double min = 100;
  double max = -100;
  int _minTemp = 4;
  int _maxTemp = 28;
  bool isSwitchedHumi = true;
  DateTime minTime;
  DateTime maxTime;
  // String result = '';

  String log = '데이터 가져오는 중';

  loc.Location location = new loc.Location();
  loc.LocationData currentLocation;
  String geolocation;

  DateTimeIntervalType currentType = DateTimeIntervalType.hours;

  @override
  void initState() {
    super.initState();
    // result = allText();
    // getCurrentLocation();
    fetchLogData();
  }

  @override
  void dispose() {
    super.dispose();
    monitoringStreamSubscription?.cancel();
  }

  void takeScreenshot() async {
    await screenshotController.capture().then((Uint8List image) {
      //Capture Done
      _imageFile = image;
    }).catchError((onError) {
      print(onError);
    });
  }

  String innerCondition(int min, int max, double temp) {
    if (temp <= max && temp >= min)
      return 'Good';
    else
      return 'Bad';
  }

  List<List<pw.TableRow>> allRow() {
    List<List<pw.TableRow>> result = [];

    int idx = -1;
    for (int i = 0; i < filteredDatas.length; i++) {
      if (i % 40 == 0) {
        ++idx;
        result.add([]);
        result[idx].add(
          tableRowDatas(["No.  ", "Temperature(°C)", "Time", "Condition  "],
              TextStyle(), filteredDatas[i].temperature),
        );
      }

      result[idx].add(
        tableRowDatas([
          (i + 1).toString(),
          filteredDatas[i].temperature.toString() + '°C',
          DateFormat('yyyy-MM-dd kk:mm')
                  .format(filteredDatas[i].timestamp.toLocal()) +
              '\n',
          //TODO: min , max 변경
          innerCondition(_minTemp, _maxTemp, filteredDatas[i].temperature)
        ], TextStyle(), filteredDatas[i].temperature),
      );
    }

    return result;
  }

  List<List<pw.Text>> allText() {
    List<List<pw.Text>> result = [];
    int listInx = -1;
    for (int i = 0; i < filteredDatas.length; i++) {
      if (i % 50 == 0) {
        result.add([]);
        listInx++;
      }

      if (i > 8) {
        result[listInx].add(pw.Text((i + 1).toString() +
            '. ' +
            filteredDatas[i].temperature.toString() +
            '°C / ' +
            //TODO: 습도 제거
            // filteredDatas[i].humidity.toString() +
            // '% / ' +
            DateFormat('yyyy-MM-dd kk:mm')
                .format(filteredDatas[i].timestamp.toLocal()) +
            '\n'));
      } else {
        result[listInx].add(pw.Text('0' +
            (i + 1).toString() +
            '. ' +
            filteredDatas[i].temperature.toString() +
            '°C / ' +
            //TODO: 습도 제거
            // filteredDatas[i].humidity.toString() +
            // '% /' +
            DateFormat('yyyy-MM-dd kk:mm')
                .format(filteredDatas[i].timestamp.toLocal()) +
            '\n'));
      }
    }

    return result;
  }

  void uploadPDF() async {
    // storage permission ask
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }

    // the downloads folder path
    final directory = await getExternalStorageDirectory();
    final path = directory.path;
    var filePath = path;
    pdf = pw.Document();
    await pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
              child: pw.Image(pw.MemoryImage(_imageFile),
                  fit: pw.BoxFit.contain)); //getting error here
        },
      ),
    );
    List<List<pw.Text>> temp = allText();
    for (int i = 0; i < temp.length; i++) {
      await pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
              // 100개 정도의 데이터
              child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [pw.Text('Log Datas\n\n')] + temp[i],
          )); //getting error here
        },
      ));
    }

    String now = DateTime.now().toString();
    File pdfFile = File(filePath + '/report_' + now + '.pdf');
    pdfFile.writeAsBytesSync(await pdf.save());
    print('pdf 저장완료');

    await Share.file('의약품 운송 결과', '/report_' + now + '.pdf',
            await pdfFile.readAsBytes(), 'application/pdf',
            text: '결과 보고서 파일입니다.')
        .then((value) => print('pdf 공유완료'))
        .onError((error, stackTrace) => print(error));
  }

  Widget textRow(List<String> titleList, TextStyle textStyle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: titleList
          .map(
            (e) => Text(
              e,
              style: textStyle,
            ),
          )
          .toList(),
    );
  }

  tableRow(List<String> attributes, TextStyle textStyle) {
    return pw.TableRow(
      children: attributes
          .map(
            (e) => pw.Text(
              "  " + e,
            ),
          )
          .toList(),
    );
  }

  tableRowDatas(List<String> attributes, TextStyle textStyle, double temper) {
    List<pw.Text> temp = [];
    if (attributes[3] == 'Condition  ') {
      return pw.TableRow(
        children: attributes
            .map(
              (e) => pw.Text(
                "  " + e,
              ),
            )
            .toList(),
      );
    } else {
      temp = attributes
          .map(
            (e) => pw.Text(
              "  " + e,
            ),
          )
          .toList();

      if (attributes[3] == 'Good') {
        return pw.TableRow(children: temp);
      } else {
        temp.removeLast();
        temp.add(pw.Text("  " + attributes[3],
            style: pw.TextStyle(color: PdfColors.red)));
        return pw.TableRow(children: temp);
      }
    }
  }

  void uploadPDF2() async {
    // storage permission ask

    var status = await Permission.storage.status;

    if (!status.isGranted) {
      await Permission.storage.request();
    }

    // the downloads folder path
    final directory = await getExternalStorageDirectory();
    final path = directory.path;
    var filePath = path;
    pdf = pw.Document();
    await pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
              child: pw.Image(pw.MemoryImage(_imageFile),
                  fit: pw.BoxFit.contain)); //getting error here
        },
      ),
    );
    List<List<pw.TableRow>> temp = allRow();

    for (int i = 0; i < temp.length; i++) {
      await pdf.addPage(pw.Page(
          orientation: pw.PageOrientation.natural,
          build: (context) => pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Log Datas',
                    style: pw.TextStyle(fontSize: 20, color: PdfColors.grey),
                  ),
                  pw.Container(
                    margin: pw.EdgeInsets.only(top: 8),
                    color: PdfColors.white,
                    child: pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.black),
                      children: temp[i],
                    ),
                  )
                ],
              )));
    }

    String now = DateTime.now().toString();
    File pdfFile = File(filePath + '/report_' + now + '.pdf');
    pdfFile.writeAsBytesSync(await pdf.save());
    print('pdf 저장완료');

    await Share.file('의약품 운송 결과', '/report_' + now + '.pdf',
            await pdfFile.readAsBytes(), 'application/pdf',
            text: '결과 보고서 파일입니다.')
        .then((value) => print('pdf 공유완료'))
        .onError((error, stackTrace) => print(error));
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
    minTime = await File(widget.currentDevice.firstPath).lastModified();
    maxTime = await File(widget.currentDevice.secondPath).lastModified();

    DeviceInfo temp =
        await DBHelper().getDevice(widget.currentDevice.getserialNumber());
    isSwitchedHumi = temp.isDesiredConditionOn == 'true' ? true : false;

    if (isSwitchedHumi == true) {
      _minTemp = temp.minHumidity;
      _maxTemp = temp.maxHumidity;
    } else {
      _minTemp = temp.minTemper;
      _maxTemp = temp.maxTemper;
    }

    await monitorCharacteristic(widget.currentDevice.peripheral);
    print('Write Start');
    print(widget.minmaxStamp.toString());
    // int tmp =
    //     ByteData.sublistView(widget.minmaxStamp.sublist(0, 3)).getInt32(0);
    // print(tmp);
    // int now = DateTime.now().millisecondsSinceEpoch;

    // print(DateTime.now().microsecondsSinceEpoch.toString());
    if (widget.currentDevice.peripheral.name == 'T301') {
      var writeCharacteristics = await widget.currentDevice.peripheral
          .writeCharacteristic(
              '00001000-0000-1000-8000-00805f9b34fb',
              '00001001-0000-1000-8000-00805f9b34fb',
              Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                  widget.currentDevice.getMacAddress() +
                  [0x04, 0x06] +
                  widget.minmaxStamp),
              true);
    } else if (widget.currentDevice.peripheral.name == 'T306') {
      var writeCharacteristics = await widget.currentDevice.peripheral
          .writeCharacteristic(
              '00001000-0000-1000-8000-00805f9b34fb',
              '00001001-0000-1000-8000-00805f9b34fb',
              Uint8List.fromList([0x55, 0xAA, 0x01, 0x06] +
                  widget.currentDevice.getMacAddress() +
                  [0x04, 0x06] +
                  widget.minmaxStamp),
              true);
    }
  }

  void _startMonitoringTemperature(
      Stream<Uint8List> characteristicUpdates, Peripheral peripheral) async {
    await monitoringStreamSubscription?.cancel();
    monitoringStreamSubscription = characteristicUpdates.listen(
      (notifyResult) async {
        // print(notifyResult.toString());
        if (notifyResult[10] == 0x05) {
          //TODO: 데이터 읽어오기
          LogData temp = transformData(notifyResult);
          if (temp.timestamp.isAfter(minTime) &&
              temp.timestamp.isBefore(maxTime)) {
            fetchDatas.add(temp);
            count++;
          }
        }
        // DataFetch End
        else if (notifyResult[10] == 0x06) {
          print('총 몇개? ' + count.toString());
          print('Read End !');
          List<LogData> tmp = [];

          for (int i = 0; i < fetchDatas.length; i++) {
            if (fetchDatas[i].temperature < _minTemp ||
                fetchDatas[i].temperature > _maxTemp) {
              unConditionalCount++;
            }
            tmp.add(fetchDatas[i]);
            if (fetchDatas[i].temperature < min) {
              setState(() {
                min = fetchDatas[i].temperature;
              });
            }
            if (fetchDatas[i].temperature > max) {
              setState(() {
                max = fetchDatas[i].temperature;
              });
            }
          }
          setState(() {
            filteredDatas = tmp;
            dataFetchEnd = true;
          });
        }
      },
      onError: (error) async {
        print("Error while monitoring characteristic \n$error");
        if (dataFetchEnd == false) {
          await showMyDialog(context);
          // Navigator.of(context).pop();
        }
      },
      cancelOnError: true,
    );
  }

  //Datalog Parsing
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
    final scaffoldKey = GlobalKey<ScaffoldState>();
    return MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            child: child,
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          );
        },
        debugShowCheckedModeBanner: false,
        title: 'OPTILO',
        theme: ThemeData(
          // primarySwatch: Colors.grey,
          primaryColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
          //canvasColor: Colors.transparent,
        ),
        home: Scaffold(
            key: scaffoldKey,
            appBar: AppBar(
              // backgroundColor: Color.fromARGB(22, 27, 32, 1),
              title: Row(
                  // mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 8,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Thermo Cert',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width / 18,
                                  fontWeight: FontWeight.w600),
                            ),
                          ]),
                    ),
                    Expanded(
                        flex: 4,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              new IconButton(
                                icon: new Icon(Icons.share, size: 30),
                                onPressed: () async {
                                  scaffoldKey.currentState
                                      .showSnackBar(SnackBar(
                                    duration: Duration(seconds: 2),
                                    content: Text('운송 결과 PDF를 생성중입니다.',
                                        style: TextStyle(fontSize: 18)),
                                  ));

                                  await takeScreenshot();
                                  // showUploadDialog(
                                  //     context, filteredDatas.length);
                                  // sendFetchData();

                                  await uploadPDF2();
                                  // final pdf = pw.Document();

                                  // pdf.addPage(
                                  //   pw.Page(
                                  //     build: (pw.Context context) =>
                                  //         pw.Container(
                                  //       child: pw.Text('Hello World!'),
                                  //     ),
                                  //   ),
                                  // );
                                  // final file = File('example.pdf');
                                  // await file.writeAsBytes(await pdf.save());
                                },
                              )
                            ])),
                  ]),
            ),
            body: Screenshot(
                controller: screenshotController,
                child: Container(
                    height: MediaQuery.of(context).size.height * 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // DefaultTabController(
                        //     length: 5,
                        //     initialIndex: 1,
                        //     child: Center(
                        //         child: Padding(
                        //             padding: const EdgeInsets.symmetric(horizontal: 1),
                        //             child: Column(
                        //                 mainAxisAlignment: MainAxisAlignment.center,
                        //                 children: <Widget>[
                        //                   Material(
                        //                     child: TabBar(
                        //                       onTap: (index) => {
                        //                         setState(() {
                        //                           currentType = toggleType(index);
                        //                         })
                        //                       },
                        //                       indicatorColor: Colors.green,
                        //                       tabs: [
                        //                         Tab(
                        //                           text: "Hour",
                        //                         ),
                        //                         Tab(
                        //                           text: "Day",
                        //                         ),
                        //                         Tab(
                        //                           text: "Week",
                        //                         ),
                        //                         Tab(
                        //                           text: "Month",
                        //                         ),
                        //                         Tab(
                        //                           text: "Year",
                        //                         ),
                        //                       ],
                        //                       labelColor: Colors.black,
                        //                       indicator: MaterialIndicator(
                        //                         height: 5,
                        //                         topLeftRadius: 8,
                        //                         topRightRadius: 8,
                        //                         horizontalPadding: 5,
                        //                         tabPosition: TabPosition.bottom,
                        //                       ),
                        //                     ),
                        //                   )
                        //                 ])))),
                        // Text(''),
                        // dataFetchEnd == true
                        //     ? Text(filteredDatas[filteredDatas.length - 1]
                        //             .timestamp
                        //             .toString()
                        //             .substring(0, 19) +
                        //         ' ~ ' +
                        //         filteredDatas[0]
                        //             .timestamp
                        //             .toString()
                        //             .substring(0, 19))
                        //     : Text(''),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            dataFetchEnd == false
                                ? Center(
                                    // height:
                                    //     MediaQuery.of(context).size.height * 0.85,
                                    child: Container(
                                    padding: EdgeInsets.all(4),
                                    height: MediaQuery.of(context).size.height *
                                        0.85,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            log,
                                            style: thinTextStyle,
                                          ),
                                          Text(''),
                                          log == '데이터 가져오는 중'
                                              ? CircularProgressIndicator(
                                                  backgroundColor:
                                                      Colors.black26,
                                                )
                                              : SizedBox(),
                                        ]),
                                  ))
                                : Container(
                                    padding: EdgeInsets.all(4),
                                    height: MediaQuery.of(context).size.height *
                                        0.85,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text('디바이스 명 : ' +
                                                    'Sensor_' +
                                                    widget.currentDevice
                                                        .peripheral.identifier
                                                        .substring(9, 11) +
                                                    widget.currentDevice
                                                        .peripheral.identifier
                                                        .substring(12, 14) +
                                                    widget.currentDevice
                                                        .peripheral.identifier
                                                        .substring(15, 17)),
                                                Text('Mac Address : ' +
                                                    widget.currentDevice
                                                        .peripheral.identifier),
                                              ],
                                            ),
                                            Image(
                                              image: AssetImage(
                                                  'images/background2.png'),
                                              fit: BoxFit.contain,
                                              width: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.3,
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.10,
                                            ),
                                          ],
                                        ),
                                        Column(
                                          children: [
                                            SfCartesianChart(
                                                primaryYAxis: NumericAxis(
                                                    maximum: 40,
                                                    interval: 10,
                                                    minimum: 0,
                                                    plotBands: <PlotBand>[
                                                      PlotBand(
                                                        horizontalTextAlignment:
                                                            TextAnchor.end,
                                                        shouldRenderAboveSeries:
                                                            false,
                                                        text: '$_minTemp°C',
                                                        textStyle: TextStyle(
                                                            color: Colors.red,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                        isVisible: true,
                                                        start: _minTemp,
                                                        end: _minTemp,
                                                        borderWidth: 2,
                                                        // color: Colors.red,
                                                        // opacity: 0.3,
                                                        // color: Color.fromRGBO(
                                                        //     255, 255, 255, 1.0),
                                                        borderColor: Colors.red,
                                                      ),
                                                      PlotBand(
                                                        horizontalTextAlignment:
                                                            TextAnchor.end,
                                                        shouldRenderAboveSeries:
                                                            false,
                                                        text: '$_maxTemp°C',
                                                        textStyle: TextStyle(
                                                            color: Colors.red,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                        isVisible: true,
                                                        start: _maxTemp,
                                                        end: _maxTemp,
                                                        borderWidth: 2,
                                                        // color: Colors.grey,
                                                        // opacity: 0.3
                                                        // color: Color.fromRGBO(
                                                        //     255, 255, 255, 1.0),
                                                        borderColor: Colors.red,
                                                      )
                                                    ]),
                                                primaryXAxis: DateTimeAxis(
                                                    labelRotation: 5,
                                                    maximumLabels: 5,
                                                    // Set name for x axis in order to use it in the callback event.
                                                    name: 'primaryXAxis',
                                                    intervalType: currentType,
                                                    majorGridLines:
                                                        MajorGridLines(
                                                            width: 1)),

                                                // Chart title
                                                title:
                                                    ChartTitle(text: '온도 그래프'),
                                                // Enable legend
                                                legend:
                                                    Legend(isVisible: false),
                                                // Enable tooltip
                                                tooltipBehavior:
                                                    TooltipBehavior(
                                                        enable: true),
                                                series: <
                                                    ChartSeries<LogData,
                                                        DateTime>>[
                                                  LineSeries<LogData, DateTime>(
                                                      dataSource: filteredDatas,
                                                      xValueMapper:
                                                          (LogData data, _) {
                                                        return data.timestamp;
                                                      },
                                                      yValueMapper:
                                                          (LogData data, _) =>
                                                              data.temperature,
                                                      name: '온도',
                                                      // Enable data label
                                                      dataLabelSettings:
                                                          DataLabelSettings(
                                                              isVisible: false))
                                                ]),
                                            Text('최저 온도 : ' +
                                                min.toString() +
                                                '°C    / ' +
                                                '최고 온도 : ' +
                                                max.toString() +
                                                '°C\n'),
                                            Text('시작 시간 : ' +
                                                DateFormat(
                                                        'yyyy-MM-dd HH:mm:ss')
                                                    .format(minTime)),
                                            Text('종료 시간 : ' +
                                                DateFormat(
                                                        'yyyy-MM-dd HH:mm:ss')
                                                    .format(maxTime)),
                                            Text('총 데이터 (1분 단위) : ' +
                                                count.toString() +
                                                '개'),
                                          ],
                                          // 1분단위 세시간 -> 180개 -> 3분단위 -> 60개 -> 3분단위 100 -> 300 분 5시간 ?
                                        ),
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            Text(
                                              '총 온도 이탈 시간 : ' +
                                                  unConditionalCount
                                                      .toString() +
                                                  '분 (' +
                                                  unConditionalCount
                                                      .toString() +
                                                  '개)\n',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w900),
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                Column(
                                                  children: [
                                                    Text('시작 이미지'),
                                                    Image.file(
                                                      File(widget.currentDevice
                                                          .firstPath),
                                                      // width: MediaQuery.of(context)
                                                      //         .size
                                                      //         .width *
                                                      //     0.35,
                                                      height:
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .height *
                                                              0.28,
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ],
                                                ),
                                                Column(children: [
                                                  Text('종료 이미지'),
                                                  Image.file(
                                                      File(widget.currentDevice
                                                          .secondPath),
                                                      // width: MediaQuery.of(context)
                                                      //         .size
                                                      //         .width *
                                                      //     0.35,
                                                      height:
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .height *
                                                              0.28)
                                                ]),
                                              ],
                                            ),
                                          ],
                                        )
                                      ],
                                    ))
                          ],
                        )
                      ],
                    )))));
  }
}

TextStyle thinTextStyle = TextStyle(
  fontSize: 24,
  color: Color.fromRGBO(20, 20, 20, 1),
  fontWeight: FontWeight.w500,
);

showMyDialog(BuildContext context) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    barrierDismissible: false,
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
                      Text("다시시도해주세요",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
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
    barrierDismissible: false,
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
