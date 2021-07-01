import 'package:flutter/material.dart';
import 'package:sigmawit/models/model_bleDevice.dart';
import 'package:sigmawit/models/model_logdata.dart';
import 'package:sigmawit/utils/util.dart';
import '../component/screen_main.dart';
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
import 'package:camera/camera.dart';
import '../component/screen_camera.dart';
import 'dart:io';
import 'package:numberpicker/numberpicker.dart';

// 데이터는 계속
// 전체 데이터 시작부터 종료까지
class EditScreen extends StatefulWidget {
  final BleDeviceItem currentDevice;

  EditScreen({this.currentDevice});

  @override
  _EditScreenState createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  String valueText = '';
  String codeDialog = '';

  StreamSubscription monitoringStreamSubscription;
  StreamSubscription<loc.LocationData> _locationSubscription;
  bool dataFetchEnd = false;
  List<LogData> fetchDatas = [];
  List<LogData> filteredDatas = [];
  int count = 0;
  BleDeviceItem selectedDevice;
  TextEditingController _textFieldController;

  int _minTemp = 2;
  int _maxTemp = 8;
  int _minHumi = 2;
  int _maxHumi = 8;
  bool isSwitchedTemp = false;
  bool isSwitchedHumi = false;

  loc.Location location = new loc.Location();
  loc.LocationData currentLocation;
  String geolocation;
  DateTimeIntervalType currentType = DateTimeIntervalType.hours;
  // _IntegerExample test;

  @override
  void initState() {
    _minTemp = 2;
    _maxTemp = 8;
    _minHumi = 2;
    _maxHumi = 8;
    selectedDevice = widget.currentDevice;

    super.initState();
    // test = _IntegerExample();
  }

  Future<void> _displayTextInputDialog(BuildContext context) async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Rename'),
            content: TextField(
              onChanged: (value) {
                setState(() {
                  valueText = value;
                });
              },
              controller: _textFieldController,
              decoration: InputDecoration(
                hintText: selectedDevice.getDeviceId(),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('CANCEL'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context);
                  });
                },
              ),
              TextButton(
                child: Text('OK'),
                onPressed: () async {
                  setState(() {
                    codeDialog = valueText;
                  });
                  // if(valueText.length > 6
                  if (valueText.substring(0, 7) == 'Sensor_') {
                    await DBHelper().createData(DeviceInfo(
                        deviceName: codeDialog,
                        isDesiredConditionOn: 'false',
                        macAddress: selectedDevice.peripheral.identifier,
                        minTemper: 2,
                        maxTemper: 8,
                        minHumidity: 2,
                        maxHumidity: 8));
                  } else {
                    await DBHelper().updateDeviceName(
                        selectedDevice.peripheral.identifier, codeDialog);
                    selectedDevice.deviceName = codeDialog;
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          );
        });
  }

  Future<void> _displayConditionInputDialog(BuildContext context) async {
    bool tempTemp = false;
    bool tempHumi = false;

    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Desired Conditions'),
            content: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(height: 16),
                Text('Min Temp (°C)',
                    style: Theme.of(context).textTheme.headline6),
                NumberPicker(
                  axis: Axis.horizontal,
                  value: _minTemp,
                  minValue: 2,
                  maxValue: 8,
                  step: 1,
                  haptics: true,
                  onChanged: (value) => setState(() => _minTemp = value),
                ),
                Text('Max Temp (°C)',
                    style: Theme.of(context).textTheme.headline6),
                NumberPicker(
                  axis: Axis.horizontal,
                  value: _maxTemp,
                  minValue: 2,
                  maxValue: 8,
                  step: 1,
                  haptics: true,
                  onChanged: (value) => setState(() => _maxTemp = value),
                ),
                Switch(
                  value: isSwitchedTemp,
                  onChanged: (value) {
                    setState(() {
                      tempTemp = value;
                    });
                  },
                  activeTrackColor: Colors.lightBlueAccent,
                  activeColor: Colors.blue,
                ),
                Divider(color: Colors.grey, height: 32),
                SizedBox(height: 16),
                Text('Min Humi (%)',
                    style: Theme.of(context).textTheme.headline6),
                NumberPicker(
                  axis: Axis.horizontal,
                  value: _minHumi,
                  minValue: 2,
                  maxValue: 8,
                  step: 1,
                  haptics: true,
                  onChanged: (value) => setState(() => _minHumi = value),
                ),
                Text('Max Humi (%)',
                    style: Theme.of(context).textTheme.headline6),
                NumberPicker(
                  axis: Axis.horizontal,
                  value: _maxHumi,
                  minValue: 2,
                  maxValue: 8,
                  step: 1,
                  haptics: true,
                  onChanged: (value) => setState(() => _maxHumi = value),
                ),
                Switch(
                  value: isSwitchedHumi,
                  onChanged: (value) {
                    setState(() {
                      tempHumi = value;
                    });
                  },
                  activeTrackColor: Colors.lightBlueAccent,
                  activeColor: Colors.blue,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: Text('CANCEL'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context);
                  });
                },
              ),
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  setState(() {
                    DBHelper().updateDeviceCondition(
                        selectedDevice.peripheral.identifier,
                        _minTemp,
                        _maxTemp,
                        _minHumi,
                        _maxHumi,
                        'false');
                    Navigator.pop(context);
                  });
                },
              ),
            ],
          );
        });
  }

  // 카메라 호출 함수
  takePicture(BuildContext context) async {
    // 사용가능한 카메라 목록 읽기
    var cameras = await availableCameras();
    // 첫 번째 카메라인 후면 카메라 사용
    var firstCamera = cameras.first;

    final cameraResult = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => TakePictureScreen(
                  camera: firstCamera,
                )));

    // if (!(cameraResult == '' || deviceList[index].firstPath != '')) {
    if (cameraResult != '' && cameraResult != null) {
      print(cameraResult.toString());
      selectedDevice.firstPath = cameraResult.toString();
      setState(() {});
      // setState(() {
      //   firstImagePath = cameraResult.toString();
      // });
    }
  }

  // 카메라 호출 함수
  takePicture2(BuildContext context) async {
    // 사용가능한 카메라 목록 읽기
    var cameras = await availableCameras();
    // 첫 번째 카메라인 후면 카메라 사용
    var firstCamera = cameras.first;

    final cameraResult = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => TakePictureScreen(
                  camera: firstCamera,
                )));

    if (cameraResult != '' && cameraResult != null) {
      print(cameraResult.toString());
      selectedDevice.secondPath = cameraResult.toString();
      setState(() {});
      // setState(() {
      //   secondImagePath = cameraResult.toString();
      // });
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'OPTILO',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ]),
            ),
            body: Center(
                child: Container(
                    decoration: BoxDecoration(
                        color: Color.fromRGBO(150, 150, 150, 1),
                        // boxShadow: [customeBoxShadow()],
                        borderRadius: BorderRadius.all(Radius.circular(5))),
                    height: MediaQuery.of(context).size.height * 0.9,
                    width: MediaQuery.of(context).size.width * 1.0,
                    child: Column(children: [
                      Expanded(
                          flex: 4,
                          child: InkWell(
                            onTap: () async {
                              // 여기 2
                              // await startRoutine(index);
                            },
                            child: Container(
                                padding: EdgeInsets.only(top: 5, left: 2),
                                width: MediaQuery.of(context).size.width * 1.0,
                                decoration: BoxDecoration(
                                    color: Color.fromRGBO(71, 71, 71, 1),
                                    //boxShadow: [customeBoxShadow()],
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(0))),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Text(' '),
                                        Image(
                                          image: AssetImage('images/T301.png'),
                                          fit: BoxFit.contain,
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.13,
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.13,
                                        ),
                                        Text('  '),
                                        Text(
                                          selectedDevice.getDeviceId(),
                                          style: whiteTextStyle,
                                        ),
                                      ],
                                    ),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Text(
                                              ' ' +
                                                  selectedDevice
                                                      .getBattery()
                                                      .toString() +
                                                  '% ',
                                              style: smallWhiteTextStyle),
                                          getbatteryImage(
                                              selectedDevice.getBattery()),
                                        ]),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        selectedDevice.firstPath == ''
                                            ? new IconButton(
                                                iconSize: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2,
                                                icon: Icon(
                                                  Icons.image,
                                                  size: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.2,
                                                ),
                                                onPressed: () {
                                                  takePicture(context);
                                                })
                                            : Image.file(
                                                File(selectedDevice.firstPath),
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2,
                                                height: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2,
                                                fit: BoxFit.contain,
                                              ),
                                        selectedDevice.secondPath == ''
                                            ? new IconButton(
                                                iconSize: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2,
                                                icon: Icon(
                                                  Icons.image,
                                                  size: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.2,
                                                ),
                                                onPressed: () {
                                                  takePicture2(context);
                                                })
                                            : Image.file(
                                                File(selectedDevice.secondPath),
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2,
                                                height: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.2)
                                      ],
                                    ),
                                  ],
                                )),
                          )),
                      Expanded(
                        flex: 2,
                        child: SizedBox(),
                      ),
                      Expanded(
                          flex: 2,
                          child: Container(
                              margin: EdgeInsets.only(top: 2),
                              padding: EdgeInsets.only(top: 5, left: 12),
                              width: MediaQuery.of(context).size.width * 0.98,
                              decoration: BoxDecoration(
                                  color: Color.fromRGBO(71, 71, 71, 1),
                                  //boxShadow: [customeBoxShadow()],
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5))),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Device Name : ',
                                          style: whiteBoldTextStyle),
                                      Text(selectedDevice.getDeviceId(),
                                          style: whiteTextStyle)
                                    ],
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          print('tap');
                                          _displayTextInputDialog(context);
                                        },
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 30,
                                          color: Colors.white,
                                        ),
                                      )
                                    ],
                                  ),
                                ],
                              ))),
                      Expanded(
                          flex: 2,
                          child: Container(
                              margin: EdgeInsets.only(top: 3),
                              padding: EdgeInsets.only(top: 5, left: 12),
                              width: MediaQuery.of(context).size.width * 0.98,
                              decoration: BoxDecoration(
                                  color: Color.fromRGBO(71, 71, 71, 1),
                                  //boxShadow: [customeBoxShadow()],
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5))),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Desired Conditions : ',
                                          style: whiteBoldTextStyle),
                                      Text(
                                          'Temperature(Min): _ _°C, Temperature(Max): _ _°C',
                                          style: smallWhiteTextStyle),
                                      Text(
                                          'Humidity(Min): _ _%, Humidity(Max): _ _%',
                                          style: smallWhiteTextStyle)
                                    ],
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          print('tap2');
                                          _displayConditionInputDialog(context);
                                        },
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 30,
                                          color: Colors.white,
                                        ),
                                      )
                                    ],
                                  ),
                                ],
                              ))),
                      Expanded(
                        flex: 2,
                        child: SizedBox(),
                      ),
                      Expanded(
                          flex: 2,
                          child: Container(
                              padding: EdgeInsets.only(top: 3, left: 12),
                              width: MediaQuery.of(context).size.width * 0.98,
                              decoration: BoxDecoration(
                                  color: Color.fromRGBO(71, 71, 71, 1),
                                  //boxShadow: [customeBoxShadow()],
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5))),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Device Mac Address : ',
                                      style: whiteBoldTextStyle),
                                  Text(selectedDevice.peripheral.identifier,
                                      style: whiteTextStyle)
                                ],
                              ))),
                      Expanded(
                          flex: 2,
                          child: TextButton(
                            onPressed: () {
                              DBHelper().deleteDevice(
                                  selectedDevice.peripheral.identifier);
                              Navigator.pop(context);
                            },
                            child: Container(
                                margin: EdgeInsets.only(
                                  top: 12,
                                ),
                                padding: EdgeInsets.only(top: 3, left: 12),
                                height: 50,
                                width: MediaQuery.of(context).size.width * 1.0,
                                decoration: BoxDecoration(
                                    color: Color.fromRGBO(0xff, 0x2e, 0x16, 1),
                                    //boxShadow: [customeBoxShadow()],
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(5))),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text('Delete', style: whiteBoldTextStyle),
                                  ],
                                )),
                          )),
                    ])))));
  }

  Widget getbatteryImage(int battery) {
    if (battery >= 75) {
      return Image(
        image: AssetImage('images/battery_100.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.08,
        height: MediaQuery.of(context).size.width * 0.08,
      );
    } else if (battery >= 50) {
      return Image(
        image: AssetImage('images/battery_75.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.08,
        height: MediaQuery.of(context).size.width * 0.08,
      );
    } else if (battery >= 35) {
      return Image(
        image: AssetImage('images/battery_50.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.08,
        height: MediaQuery.of(context).size.width * 0.08,
      );
    } else if (battery >= 15)
      return Image(
        image: AssetImage('images/battery_25.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.08,
        height: MediaQuery.of(context).size.width * 0.08,
      );
  }
}

TextStyle thinTextStyle = TextStyle(
  fontSize: 20,
  color: Color.fromRGBO(20, 20, 20, 1),
  fontWeight: FontWeight.w200,
);

showMyDialog(BuildContext context) {
  bool manuallyClosed = false;
  return new AlertDialog(
    contentPadding: const EdgeInsets.all(16.0),
    content: new Row(
      children: <Widget>[
        new Expanded(
          child: new TextField(
            autofocus: true,
            decoration: new InputDecoration(
                labelText: 'Full Name', hintText: 'eg. John Smith'),
          ),
        )
      ],
    ),
    actions: <Widget>[
      new TextButton(
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Text('CANCEL'),
      ),
      new TextButton(
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Text('CANCEL'),
      )
    ],
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

TextStyle whiteBoldTextStyle = TextStyle(
  fontSize: 18,
  color: Color.fromRGBO(255, 255, 255, 1),
  fontWeight: FontWeight.w600,
);
TextStyle whiteTextStyle = TextStyle(
  fontSize: 13,
  color: Color.fromRGBO(255, 255, 255, 1),
  fontWeight: FontWeight.w300,
);
TextStyle smallWhiteTextStyle = TextStyle(
  fontSize: 12,
  color: Color.fromRGBO(255, 255, 255, 1),
  fontWeight: FontWeight.w300,
);
