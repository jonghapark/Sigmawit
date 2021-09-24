import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sigmawit/component/screen_detail.dart';
import 'package:sigmawit/models/model_logdata.dart';
import '../models/model_bleDevice.dart';
import '../utils/util.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:location/location.dart' as loc;
import 'package:geocoder/geocoder.dart';
import 'package:intl/intl.dart';
import '../component/screen_camera.dart';
import '../component/screen_edit.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class Scanscreen extends StatefulWidget {
  @override
  ScanscreenState createState() => ScanscreenState();
}

class ScanscreenState extends State<Scanscreen> {
  BleManager _bleManager = BleManager();
  bool _isScanning = false;
  bool _connected = false;
  String currentMode = 'normal';
  String message = '';
  Peripheral _curPeripheral; // 연결된 장치 변수
  List<BleDeviceItem> deviceList = []; // BLE 장치 리스트 변수
  List<DeviceInfo> savedDeviceList = []; // 저장된 BLE 장치 리스트 변수
  List<String> savedList = []; // 추가된 장치 리스트 변수
  //List<BleDeviceItem> myDeviceList = [];
  String _statusText = ''; // BLE 상태 변수
  loc.LocationData currentLocation;
  int dataSize = 0;
  loc.Location location = new loc.Location();
  int processState = 1;
  StreamSubscription<loc.LocationData> _locationSubscription;
  StreamSubscription monitoringStreamSubscription;
  String _error;
  String geolocation;
  String currentDeviceName = '';
  Timer _timer;
  int _start = 0;
  bool isStart = false;
  Map<String, String> idMapper;
  // double width;
  TextEditingController _textFieldController;
  String currentState = '';

  String firstImagePath = '';
  String secondImagePath = '';
  Future<List<DeviceInfo>> _allDeviceTemp;

  // Future<List<DateTime>> allDatetime;

  String currentTemp;
  String currentHumi;

  @override
  void initState() {
    // _allDeviceTemp = DBHelper().getAllDevices();

    super.initState();
    // getCurrentLocation();
    currentDeviceName = '';
    currentTemp = '-';
    currentHumi = '-';
    init();
  }

  @override
  void dispose() {
    // ->> 사라진 위젯에서 cancel하려고 해서 에러 발생
    super.dispose();
    // _stopMonitoringTemperature();
    _bleManager.destroyClient();
  }

  endRoutine(value, index) {
    if (value != null) {
      print("??? " + deviceList[index].getserialNumber());
      savedList.remove(deviceList[index].getserialNumber());
      deviceList.remove(deviceList[index]);
      print('저장목록 : ' + savedList.toString());
      print('디바이스목록 : ' + deviceList.toString());
    }
    setState(() {});
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
        "tra_impact": data.lex
      });

      // print(await client.get(uriResponse.body.['uri']));
    } catch (e) {
      print(e);
      return null;
    } finally {
      print('send !');
      client.close();
    }
  }

  // 카메라 호출 함수
  takePicture(BuildContext context, int index) async {
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
      deviceList[index].firstPath = cameraResult.toString();
      deviceList[index].secondPath = '';
      setState(() {});
      await DBHelper().updateImagePath(deviceList[index].getserialNumber(),
          cameraResult.toString(), 'first');

      // setState(() {
      //   firstImagePath = cameraResult.toString();
      // });

    }
    return cameraResult;
  }

  // 카메라 호출 함수
  takePicture2(BuildContext context, int index) async {
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
      deviceList[index].secondPath = cameraResult.toString();
      await DBHelper().updateImagePath(deviceList[index].getserialNumber(),
          cameraResult.toString(), 'second');
      setState(() {});

      // setState(() {
      //   secondImagePath = cameraResult.toString();
      // });
    }
    return cameraResult;
  }

  Future<void> monitorCharacteristic(Peripheral peripheral, flag) async {
    await _runWithErrorHandling(() async {
      Service service = await peripheral.services().then((services) =>
          services.firstWhere((service) =>
              service.uuid == '00001000-0000-1000-8000-00805f9b34fb'));

      List<Characteristic> characteristics = await service.characteristics();
      Characteristic characteristic = characteristics.firstWhere(
          (characteristic) =>
              characteristic.uuid == '00001002-0000-1000-8000-00805f9b34fb');

      _startMonitoringTemperature(
          characteristic.monitor(transactionId: "monitor"), peripheral, flag);
    });
  }

  Uint8List getMinMaxTimestamp(Uint8List notifyResult) {
    return notifyResult.sublist(12, 18);
  }

  void _stopMonitoringTemperature() async {
    monitoringStreamSubscription?.cancel();
  }

  void _startMonitoringTemperature(Stream<Uint8List> characteristicUpdates,
      Peripheral peripheral, flag) async {
    monitoringStreamSubscription?.cancel();

    monitoringStreamSubscription = characteristicUpdates.listen(
      (notifyResult) async {
        // print('혹시 이거임 ?' + notifyResult.toString());
        if (notifyResult[10] == 0x0a) {
          // FIXME: 기존 데이터 삭제 후 ( 다이얼로그 종료 ) -> ( 운송 시작 다이얼로그 ) 변경
          await showMyDialog_StartTransport(context);
          Navigator.of(context).pop();
        }
        if (notifyResult[10] == 0x03) {
          int index = -1;
          for (var i = 0; i < deviceList.length; i++) {
            if (deviceList[i].peripheral.identifier == peripheral.identifier) {
              index = i;
              break;
            }
          }

          if (index != -1) {
            Uint8List minmaxStamp = getMinMaxTimestamp(notifyResult);
            print('여기 걸리나 ?');

            if (flag == 0) {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => DetailScreen(
                          currentDevice: deviceList[index],
                          minmaxStamp: minmaxStamp))).then((value) =>
                  value == null ? Navigator.pop(context) : print(''));
              await _stopMonitoringTemperature();
            } else {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => EditScreen(
                            currentDevice: deviceList[index],
                          ))).then((value) => print(value));
              await _stopMonitoringTemperature();
            }
          }
        }
      },
      onError: (error) {
        final BleError temperrors = error;
        if (temperrors.errorCode.value == 201) {
          print('그르게');
        }
        print("Error while monitoring characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  void startRoutine(int index, flag) async {
    // 여기 !
    await monitorCharacteristic(deviceList[index].peripheral, flag);
    String unixTimestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
            .toInt()
            .toRadixString(16);
    Uint8List timestamp = Uint8List.fromList([
      int.parse(unixTimestamp.substring(0, 2), radix: 16),
      int.parse(unixTimestamp.substring(2, 4), radix: 16),
      int.parse(unixTimestamp.substring(4, 6), radix: 16),
      int.parse(unixTimestamp.substring(6, 8), radix: 16),
    ]);

    Uint8List macaddress = deviceList[index].getMacAddress();
    print('쓰기 시작 ');
    if (flag == 0) {
      if (deviceList[index].peripheral.name == 'T301') {
        var writeCharacteristics = await deviceList[index]
            .peripheral
            .writeCharacteristic(
                '00001000-0000-1000-8000-00805f9b34fb',
                '00001001-0000-1000-8000-00805f9b34fb',
                Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                    deviceList[index].getMacAddress() +
                    [0x02, 0x04] +
                    timestamp),
                true);
      } else if (deviceList[index].peripheral.name == 'T306') {
        var writeCharacteristics = await deviceList[index]
            .peripheral
            .writeCharacteristic(
                '00001000-0000-1000-8000-00805f9b34fb',
                '00001001-0000-1000-8000-00805f9b34fb',
                Uint8List.fromList([0x55, 0xAA, 0x01, 0x06] +
                    deviceList[index].getMacAddress() +
                    [0x02, 0x04] +
                    timestamp),
                true);
      }
    } else if (flag == 1) {
      // 데이터 삭제 시작
      if (deviceList[index].peripheral.name == 'T301') {
        var writeCharacteristics = await deviceList[index]
            .peripheral
            .writeCharacteristic(
                '00001000-0000-1000-8000-00805f9b34fb',
                '00001001-0000-1000-8000-00805f9b34fb',
                Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                    deviceList[index].getMacAddress() +
                    [0x09, 0x01, 0x01]),
                true);
      } else if (deviceList[index].peripheral.name == 'T306') {
        var writeCharacteristics = await deviceList[index]
            .peripheral
            .writeCharacteristic(
                '00001000-0000-1000-8000-00805f9b34fb',
                '00001001-0000-1000-8000-00805f9b34fb',
                Uint8List.fromList([0x55, 0xAA, 0x01, 0x06] +
                    deviceList[index].getMacAddress() +
                    [0x09, 0x01, 0x01]),
                true);
      }
    }
  }

  // 타이머 시작
  // 00:00:00
  void startTimer() {
    if (isStart == true) return;
    const oneSec = const Duration(seconds: 15);
    _timer = new Timer.periodic(
      oneSec,
      (Timer timer) => setState(
        () {
          if (isStart == false) isStart = true;
          _start = _start + 1;
          // if (_start % 5 == 0) {
          print(_start);
          _checkPermissions();
          _listenLocation();
          // }
          // date = (new DateTime(1996,5,23, _start~/3600 ,
          //  (_start-(_start~/3600)*3600) ~/ 60 ,
          //  ((_start-(_start~/3600)*3600) ~/ 60 ) * 60
          //  );
        },
      ),
    );
  }

  Future<void> _listenLocation() async {
    _locationSubscription =
        location.onLocationChanged.handleError((dynamic err) {
      setState(() {
        _error = err.code;
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
          _error = null;
          this.currentLocation = currentLocation;

          this.geolocation = first.addressLine;
        });
      }
    });
  }

  Future<Post> sendData(Data data) async {
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
        "tra_impact": data.lex
      });
      // print(await client.get(uriResponse.body.['uri']));
    } finally {
      client.close();
    }
  }

  // BLE 초기화 함수
  void init() async {
    //ble 매니저 생성
    // savedDeviceList = await DBHelper().getAllDevices();
    savedList = await DBHelper().getAllSavedList();
    setState(() {});
    await _bleManager
        .createClient(
            restoreStateIdentifier: "hello",
            restoreStateAction: (peripherals) {
              peripherals?.forEach((peripheral) {
                print("Restored peripheral: ${peripheral.name}");
              });
            })
        .catchError((e) => print("Couldn't create BLE client  $e"))
        .then((_) => _checkPermissions()) //매니저 생성되면 권한 확인
        .catchError((e) => print("Permission check error $e"));
  }

  // 권한 확인 함수 권한 없으면 권한 요청 화면 표시, 안드로이드만 상관 있음
  _checkPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.location.request().isGranted) {
        print('입장하냐?');
        scan();
        return;
      }
      Map<Permission, PermissionStatus> statuses =
          await [Permission.location].request();
      if (statuses[Permission.location].toString() ==
          "PermissionStatus.granted") {
        //getCurrentLocation();
        scan();
      }
    } else {
      scan();
    }
  }

  //장치 화면에 출력하는 위젯 함수
  list2() {
    if (deviceList?.isEmpty == true) {
      return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [customeBoxShadow()],
              borderRadius: BorderRadius.all(Radius.circular(5))),
          height: MediaQuery.of(context).size.height * 0.33,
          width: MediaQuery.of(context).size.width * 0.99,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      '우측 상단의 + 버튼을 이용하여 \n',
                      style: lastUpdateTextStyle(context),
                    ),
                    Text(
                      '기기를 등록해주세요 !',
                      style: lastUpdateTextStyle(context),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text('또는, 블루투스가 켜져있나 확인해주세요.\n',
                        style: lastUpdateTextStyle(context)),
                    InkWell(
                        onTap: () {
                          _isScanning = false;
                          scan();
                        },
                        child: Column(
                          children: [
                            Icon(
                              Icons.refresh,
                              size: 40,
                              color: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
                            ),
                            Text('새로고침', style: lastUpdateTextStyle(context))
                          ],
                        ))
                  ],
                )
              ]));
    } else {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: deviceList.length,
        itemBuilder: (BuildContext context, int index) {
          return Container(
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [customeBoxShadow()],
                borderRadius: BorderRadius.all(Radius.circular(5))),
            height: MediaQuery.of(context).size.height * 0.33,
            width: MediaQuery.of(context).size.width * 0.99,
            child: Column(children: [
              Expanded(
                  flex: 4,
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => EditScreen(
                                    currentDevice: deviceList[index],
                                  ))).then((value) => {
                            endRoutine(value, index),
                          });
                      // 여기 2
                      // await startRoutine(index);
                    },
                    child: Container(
                        padding: EdgeInsets.only(top: 5, left: 2),
                        width: MediaQuery.of(context).size.width * 0.98,
                        decoration: BoxDecoration(
                            color: Color.fromRGBO(71, 71, 71, 1),
                            //boxShadow: [customeBoxShadow()],
                            borderRadius: BorderRadius.all(Radius.circular(5))),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(' '),
                                Image(
                                  image: AssetImage('images/T301.png'),
                                  fit: BoxFit.contain,
                                  width:
                                      MediaQuery.of(context).size.width * 0.10,
                                  height:
                                      MediaQuery.of(context).size.width * 0.10,
                                ),
                                Text(' '),
                                FutureBuilder(
                                    future: DBHelper().getAllDevices(),
                                    builder: (BuildContext context,
                                        AsyncSnapshot<List<DeviceInfo>>
                                            snapshot) {
                                      if (snapshot.hasData) {
                                        List<DeviceInfo> devices =
                                            snapshot.data;
                                        String temp = '';
                                        for (int i = 0;
                                            i < devices.length;
                                            i++) {
                                          // print(devices[i].macAddress);
                                          // print(devices[i].macAddress);
                                          // print(deviceList[index]
                                          //     .getserialNumber());
                                          if (devices[i].macAddress ==
                                              deviceList[index]
                                                  .getserialNumber()) {
                                            temp = devices[i].deviceName;

                                            deviceList[index].firstPath =
                                                devices[i].firstPath;
                                            deviceList[index].secondPath =
                                                devices[i].secondPath;

                                            break;
                                          }
                                        }
                                        if (temp == '') {
                                          return Text(
                                            deviceList[index].getDeviceId(),
                                            style: whiteTextStyle(context),
                                          );
                                        } else {
                                          deviceList[index].deviceName = temp;

                                          return Text(
                                            temp,
                                            style: whiteTextStyle(context),
                                          );
                                        }
                                      } else {
                                        return Text(
                                          deviceList[index].getDeviceId(),
                                          style: whiteTextStyle(context),
                                        );
                                      }
                                    })
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                deviceList[index].firstPath == ''
                                    ? new IconButton(
                                        iconSize:
                                            MediaQuery.of(context).size.width *
                                                0.15,
                                        icon: Icon(
                                          Icons.image,
                                          size: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                        ),
                                        onPressed: () async {
                                          // confirmPicture(
                                          //     context,
                                          //     deviceList[index].firstPath,
                                          //     'first',
                                          //     index);

                                          String pictureResult =
                                              await takePicture(context, index);
                                          if (pictureResult != null &&
                                              pictureResult != '') {
                                            deviceList[index].firstPath =
                                                pictureResult;
                                            confirmPicture(
                                                context,
                                                deviceList[index].firstPath,
                                                'first',
                                                index);
                                          }
                                        })
                                    : InkWell(
                                        onTap: () {
                                          confirmPicture(
                                              context,
                                              deviceList[index].firstPath,
                                              'first',
                                              index);
                                        },
                                        child: Image.file(
                                          File(deviceList[index].firstPath),
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                          fit: BoxFit.fitHeight,
                                        ),
                                      ),
                                deviceList[index].secondPath == ''
                                    ? new IconButton(
                                        iconSize:
                                            MediaQuery.of(context).size.width *
                                                0.15,
                                        icon: Icon(
                                          Icons.image,
                                          size: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                        ),
                                        onPressed: () async {
                                          // confirmPicture(
                                          //     context,
                                          //     deviceList[index].secondPath,
                                          //     'second',
                                          //     index);

                                          String pictureResult =
                                              await takePicture2(
                                                  context, index);
                                          if (pictureResult != null &&
                                              pictureResult != '') {
                                            deviceList[index].secondPath =
                                                pictureResult;
                                            confirmPicture(
                                                context,
                                                deviceList[index].secondPath,
                                                'second',
                                                index);
                                          }
                                        })
                                    : InkWell(
                                        onTap: () {
                                          confirmPicture(
                                              context,
                                              deviceList[index].secondPath,
                                              'second',
                                              index);
                                        },
                                        child: Image.file(
                                            File(deviceList[index].secondPath),
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.15,
                                            height: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.15),
                                      )
                              ],
                            )
                          ],
                        )),
                  )),
              Expanded(
                flex: 3,
                child: InkWell(
                    onTap: () async {
                      // await connect(index, 0);
                      // 여기 2
                      // await startRoutine(index);
                    },

                    // onTap: Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (context) => DetailScreen()(
                    //               camera: firstCamera,
                    //             ))),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Row(
                                children: [
                                  Image(
                                    image:
                                        AssetImage('images/ic_thermometer.png'),
                                    fit: BoxFit.cover,
                                    width: MediaQuery.of(context).size.width *
                                        0.10,
                                    height: MediaQuery.of(context).size.width *
                                        0.10,
                                  ),
                                  Text(
                                      deviceList[index]
                                              .getTemperature()
                                              .toString() +
                                          '°C',
                                      style: bigTextStyle(context)),
                                ],
                              ),
                              Row(
                                children: [
                                  Image(
                                    image: AssetImage('images/ic_humidity.png'),
                                    fit: BoxFit.cover,
                                    width: MediaQuery.of(context).size.width *
                                        0.09,
                                    height: MediaQuery.of(context).size.width *
                                        0.09,
                                  ),
                                  Text(
                                    deviceList[index].getHumidity().toString() +
                                        '%',
                                    style: bigTextStyle(context),
                                  )
                                ],
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Row(
                                children: [
                                  Text('시작 시간 : '),
                                  FutureBuilder(
                                      future: File(deviceList[index].firstPath)
                                          .lastModified(),
                                      builder: (BuildContext context,
                                          AsyncSnapshot<DateTime> snapshot) {
                                        if (snapshot.hasData) {
                                          DateTime mintime = snapshot.data;
                                          return Text(DateFormat('dd일 HH:mm:ss')
                                              .format(mintime));
                                        } else {
                                          return Text('--일 --:--:--');
                                        }
                                      }),
                                ],
                              ),
                              Row(
                                children: [
                                  Text('종료 시간 : '),
                                  FutureBuilder(
                                      future: File(deviceList[index].secondPath)
                                          .lastModified(),
                                      builder: (BuildContext context,
                                          AsyncSnapshot<DateTime> snapshot) {
                                        if (snapshot.hasData) {
                                          DateTime maxtime = snapshot.data;
                                          return Text(DateFormat('dd일 HH:mm:ss')
                                              .format(maxtime));
                                        } else {
                                          return Text('--일 --:--:--');
                                        }
                                      }),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        getbatteryImage(
                                            deviceList[index].getBattery()),
                                        Text(
                                          '  ' +
                                              deviceList[index]
                                                  .getBattery()
                                                  .toString() +
                                              '%',
                                          style: lastUpdateTextStyle(context),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 8,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '최근 업데이트  ',
                                      style: lastUpdateTextStyle(context),
                                    ),
                                    deviceList[index].lastUpdateTime != null
                                        ? Text(
                                            DateFormat('yyyy-MM-dd - HH:mm')
                                                .format(deviceList[index]
                                                    .lastUpdateTime),
                                            style: updateTextStyle(context),
                                          )
                                        : Text(
                                            '-',
                                            style: updateTextStyle(context),
                                          ),
                                    Text('  ')
                                  ],
                                ),
                              ),
                            ],
                          )
                        ])),
              )
            ]),
          );
        },
        //12,13 온도
        separatorBuilder: (BuildContext context, int index) {
          return Divider();
        },
        // itemBuilder: (context, index) {
        //   return ListTile(
        //       title: Text(deviceList[index].deviceName),
        //       subtitle: Text(deviceList[index].peripheral.identifier),
        //       trailing: Text("${deviceList[index].rssi}"),
        //       onTap: () {
        //         // itemCount: deviceList.length,
        //         // itemBuilder: (context, index) () ListView.builder()
        //         // 처음에 1.. 시작하면 2, connected 3 disconnected 4
        //         // 리스트중 한개를 탭(터치) 하면 해당 디바이스와 연결을 시도한다.
        //         // bool currentState = false;
        //         // setState(() {
        //         //   processState = 2;
        //         // });
        //         // connect(index);
        //       });
        // },
      );
    }
  }

  //장치 화면에 출력하는 위젯 함수
  list() {
    if (deviceList?.isEmpty == true) {
      return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [customeBoxShadow()],
              borderRadius: BorderRadius.all(Radius.circular(5))),
          height: MediaQuery.of(context).size.height * 0.33,
          width: MediaQuery.of(context).size.width * 0.99,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      '우측 상단의 + 버튼을 이용하여 \n',
                      style: lastUpdateTextStyle(context),
                    ),
                    Text(
                      '기기를 등록해주세요 !',
                      style: lastUpdateTextStyle(context),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text('또는, 블루투스가 켜져있나 확인해주세요.\n',
                        style: lastUpdateTextStyle(context)),
                    InkWell(
                        onTap: () {
                          _isScanning = false;
                          scan();
                        },
                        child: Column(
                          children: [
                            Icon(
                              Icons.refresh,
                              size: 40,
                              color: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
                            ),
                            Text('새로고침', style: lastUpdateTextStyle(context))
                          ],
                        ))
                  ],
                )
              ]));
    } else {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: deviceList.length,
        itemBuilder: (BuildContext context, int index) {
          return Container(
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [customeBoxShadow()],
                borderRadius: BorderRadius.all(Radius.circular(5))),
            height: MediaQuery.of(context).size.height * 0.33,
            width: MediaQuery.of(context).size.width * 0.99,
            child: Column(children: [
              Expanded(
                  flex: 4,
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => EditScreen(
                                    currentDevice: deviceList[index],
                                  ))).then((value) => {
                            endRoutine(value, index),
                          });
                      // 여기 2
                      // await startRoutine(index);
                    },
                    child: Container(
                        padding: EdgeInsets.only(top: 5, left: 2),
                        width: MediaQuery.of(context).size.width * 0.98,
                        decoration: BoxDecoration(
                            color: Color.fromRGBO(71, 71, 71, 1),
                            //boxShadow: [customeBoxShadow()],
                            borderRadius: BorderRadius.all(Radius.circular(5))),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(' '),
                                Image(
                                  image: AssetImage('images/T301.png'),
                                  fit: BoxFit.contain,
                                  width:
                                      MediaQuery.of(context).size.width * 0.10,
                                  height:
                                      MediaQuery.of(context).size.width * 0.10,
                                ),
                                Text(' '),
                                FutureBuilder(
                                    future: _allDeviceTemp,
                                    builder: (BuildContext context,
                                        AsyncSnapshot<List<DeviceInfo>>
                                            snapshot) {
                                      if (snapshot.hasData) {
                                        List<DeviceInfo> devices =
                                            snapshot.data;
                                        String temp = '';
                                        for (int i = 0;
                                            i < devices.length;
                                            i++) {
                                          // print(devices[i].macAddress);
                                          // print(devices[i].macAddress);
                                          // print(deviceList[index]
                                          //     .getserialNumber());
                                          if (devices[i].macAddress ==
                                              deviceList[index]
                                                  .getserialNumber()) {
                                            temp = devices[i].deviceName;

                                            deviceList[index].firstPath =
                                                devices[i].firstPath;
                                            deviceList[index].secondPath =
                                                devices[i].secondPath;

                                            break;
                                          }
                                        }
                                        if (temp == '') {
                                          return Text(
                                            deviceList[index].getDeviceId(),
                                            style: whiteTextStyle(context),
                                          );
                                        } else {
                                          deviceList[index].deviceName = temp;

                                          return Text(
                                            temp,
                                            style: whiteTextStyle(context),
                                          );
                                        }
                                      } else {
                                        return Text(
                                          deviceList[index].getDeviceId(),
                                          style: whiteTextStyle(context),
                                        );
                                      }
                                    })
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                deviceList[index].firstPath == ''
                                    ? new IconButton(
                                        iconSize:
                                            MediaQuery.of(context).size.width *
                                                0.15,
                                        icon: Icon(
                                          Icons.image,
                                          size: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                        ),
                                        onPressed: () async {
                                          // confirmPicture(
                                          //     context,
                                          //     deviceList[index].firstPath,
                                          //     'first',
                                          //     index);

                                          String pictureResult =
                                              await takePicture(context, index);
                                          if (pictureResult != null &&
                                              pictureResult != '') {
                                            deviceList[index].firstPath =
                                                pictureResult;
                                            String temps = await confirmPicture(
                                                context,
                                                deviceList[index].firstPath,
                                                'first',
                                                index);
                                            print('Result :' + temps);
                                          }
                                        })
                                    : InkWell(
                                        onTap: () async {
                                          String temps = await confirmPicture(
                                              context,
                                              deviceList[index].firstPath,
                                              'first',
                                              index);
                                          // print('Result :' + temps);
                                          if (temps != null && temps != '') {
                                            deviceList[index].firstPath = temps;
                                            setState(() {
                                              deviceList[index].firstPath =
                                                  temps;
                                            });
                                          }

                                          // print(
                                          //     this.deviceList[index].firstPath);
                                          // print(deviceList[index].firstPath);
                                        },
                                        child: Image.file(
                                          File(deviceList[index].firstPath),
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                          fit: BoxFit.fitHeight,
                                        ),
                                      ),
                                deviceList[index].secondPath == ''
                                    ? new IconButton(
                                        iconSize:
                                            MediaQuery.of(context).size.width *
                                                0.15,
                                        icon: Icon(
                                          Icons.image,
                                          size: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.15,
                                        ),
                                        onPressed: () async {
                                          // confirmPicture(
                                          //     context,
                                          //     deviceList[index].secondPath,
                                          //     'second',
                                          //     index);

                                          String pictureResult =
                                              await takePicture2(
                                                  context, index);
                                          if (pictureResult != null &&
                                              pictureResult != '') {
                                            deviceList[index].secondPath =
                                                pictureResult;
                                            setState(() {
                                              deviceList[index].secondPath =
                                                  pictureResult;
                                            });
                                            print('before : ' +
                                                deviceList[index].secondPath);
                                            await confirmPicture(
                                                context,
                                                deviceList[index].secondPath,
                                                'second',
                                                index);

                                            print('???' +
                                                deviceList[index].secondPath);
                                          }
                                        })
                                    : InkWell(
                                        onTap: () async {
                                          String temps = await confirmPicture(
                                              context,
                                              deviceList[index].secondPath,
                                              'second',
                                              index);
                                          if (temps != null && temps != '') {
                                            deviceList[index].secondPath =
                                                temps;
                                            setState(() {
                                              deviceList[index].secondPath =
                                                  temps;
                                            });
                                          }
                                        },
                                        child: Image.file(
                                            File(deviceList[index].secondPath),
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.15,
                                            height: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.15),
                                      )
                              ],
                            )
                          ],
                        )),
                  )),
              Expanded(
                flex: 3,
                child: InkWell(
                    onTap: () async {
                      // await connect(index, 0);
                      // 여기 2
                      // await startRoutine(index);
                    },

                    // onTap: Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (context) => DetailScreen()(
                    //               camera: firstCamera,
                    //             ))),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Row(
                                children: [
                                  Image(
                                    image:
                                        AssetImage('images/ic_thermometer.png'),
                                    fit: BoxFit.cover,
                                    width: MediaQuery.of(context).size.width *
                                        0.10,
                                    height: MediaQuery.of(context).size.width *
                                        0.10,
                                  ),
                                  Text(
                                      deviceList[index]
                                              .getTemperature()
                                              .toString() +
                                          '°C',
                                      style: bigTextStyle(context)),
                                ],
                              ),
                              Row(
                                children: [
                                  Image(
                                    image: AssetImage('images/ic_humidity.png'),
                                    fit: BoxFit.cover,
                                    width: MediaQuery.of(context).size.width *
                                        0.09,
                                    height: MediaQuery.of(context).size.width *
                                        0.09,
                                  ),
                                  Text(
                                    deviceList[index].getHumidity().toString() +
                                        '%',
                                    style: bigTextStyle(context),
                                  )
                                ],
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Row(
                                children: [
                                  Text('시작 시간 : '),
                                  FutureBuilder(
                                      future: File(deviceList[index].firstPath)
                                          .lastModified(),
                                      builder: (BuildContext context,
                                          AsyncSnapshot<DateTime> snapshot) {
                                        if (snapshot.hasData) {
                                          DateTime mintime = snapshot.data;

                                          return Text(DateFormat('dd일 HH:mm:ss')
                                              .format(mintime));
                                        } else {
                                          return Text('--일 --:--:--');
                                        }
                                      }),
                                ],
                              ),
                              Row(
                                children: [
                                  Text('종료 시간 : '),
                                  FutureBuilder(
                                      future: File(deviceList[index].secondPath)
                                          .lastModified(),
                                      builder: (BuildContext context,
                                          AsyncSnapshot<DateTime> snapshot) {
                                        if (snapshot.hasData) {
                                          DateTime maxtime = snapshot.data;
                                          return Text(DateFormat('dd일 HH:mm:ss')
                                              .format(maxtime));
                                        } else {
                                          return Text('--일 --:--:--');
                                        }
                                      }),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        getbatteryImage(
                                            deviceList[index].getBattery()),
                                        Text(
                                          '  ' +
                                              deviceList[index]
                                                  .getBattery()
                                                  .toString() +
                                              '%',
                                          style: lastUpdateTextStyle(context),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 8,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '최근 업데이트  ',
                                      style: lastUpdateTextStyle(context),
                                    ),
                                    deviceList[index].lastUpdateTime != null
                                        ? Text(
                                            DateFormat('yyyy-MM-dd - HH:mm')
                                                .format(deviceList[index]
                                                    .lastUpdateTime),
                                            style: updateTextStyle(context),
                                          )
                                        : Text(
                                            '-',
                                            style: updateTextStyle(context),
                                          ),
                                    Text('  ')
                                  ],
                                ),
                              ),
                            ],
                          )
                        ])),
              )
            ]),
          );
        },
        //12,13 온도
        separatorBuilder: (BuildContext context, int index) {
          return Divider();
        },
        // itemBuilder: (context, index) {
        //   return ListTile(
        //       title: Text(deviceList[index].deviceName),
        //       subtitle: Text(deviceList[index].peripheral.identifier),
        //       trailing: Text("${deviceList[index].rssi}"),
        //       onTap: () {
        //         // itemCount: deviceList.length,
        //         // itemBuilder: (context, index) () ListView.builder()
        //         // 처음에 1.. 시작하면 2, connected 3 disconnected 4
        //         // 리스트중 한개를 탭(터치) 하면 해당 디바이스와 연결을 시도한다.
        //         // bool currentState = false;
        //         // setState(() {
        //         //   processState = 2;
        //         // });
        //         // connect(index);
        //       });
        // },
      );
    }
  }

  // 1. 엑셀 2. 서버구조 3. 영어 과제
  //scan 함수
  void scan() async {
    if (!_isScanning) {
      print('스캔시작');
      deviceList.clear(); //기존 장치 리스트 초기화
      //SCAN 시작
      if (Platform.isAndroid) {
        _bleManager.startPeripheralScan(scanMode: ScanMode.lowLatency).listen(
            (scanResult) {
          //listen 이벤트 형식으로 장치가 발견되면 해당 루틴을 계속 탐.
          //periphernal.name이 없으면 advertisementData.localName확인 이것도 없다면 unknown으로 표시
          //print(scanResult.peripheral.name);
          var name = scanResult.peripheral.name ??
              scanResult.advertisementData.localName ??
              "Unknown";
          // 기존에 존재하는 장치면 업데이트
          // print('lenght: ' + deviceList.length.toString());
          var findDevice = deviceList.any((element) {
            if (element.peripheral.identifier ==
                scanResult.peripheral.identifier) {
              element.peripheral = scanResult.peripheral;
              element.advertisementData = scanResult.advertisementData;
              element.rssi = scanResult.rssi;

              if (currentLocation != null) {
                BleDeviceItem currentItem = new BleDeviceItem(
                    name,
                    scanResult.rssi,
                    scanResult.peripheral,
                    scanResult.advertisementData,
                    'scan');

                Data sendData = new Data(
                  battery: currentItem.getBattery().toString(),
                  deviceName:
                      'OP_' + currentItem.getDeviceId().toString().substring(7),
                  humi: currentItem.getHumidity().toString(),
                  temper: currentItem.getTemperature().toString(),
                  lat: currentLocation.latitude.toString() ?? '',
                  lng: currentLocation.longitude.toString() ?? '',
                  time: new DateTime.now().toString(),
                  lex: '',
                );
                // sendtoServer(sendData);
              }

              return true;
            }
            return false;
          });
          // 새로 발견된 장치면 추가
          if (!findDevice) {
            // if (scanResult.peripheral.identifier.substring(0, 8) == 'A4:C1:38') {
            //   print('이거임 : ' +
            //       scanResult.advertisementData.manufacturerData.toString());
            // }

            if (name != "Unknown") {
              // print(name);
              // if (name.substring(0, 3) == 'IOT') {
              if (name != null) {
                if (name.substring(0, 4) == 'T301' ||
                    name.substring(0, 4) == 'T306') {
                  BleDeviceItem currentItem = new BleDeviceItem(
                      name,
                      scanResult.rssi,
                      scanResult.peripheral,
                      scanResult.advertisementData,
                      'scan');
                  bool isExist = false;

                  for (int i = 0; i < savedList.length; i++) {
                    // print(savedList[i] + ' ' + currentItem.getserialNumber());
                    if (savedList[i] == currentItem.getserialNumber()) {
                      isExist = true;
                      break;
                    }
                  }

                  print(currentItem.peripheral.identifier);
                  print(currentItem.getserialNumber().toString());
                  // print(savedList.toString());

                  if (isExist) {
                    print('인 !');
                    print(savedList);
                    deviceList.add(currentItem);
                    // var temp
                    //     DBHelper().getDevice(scanResult.peripheral.identifier);

                    // if (temp == Null) {
                    //   print('Add ! -> ' + currentItem.getserialNumber());
                    //   // DBHelper().createData(new DeviceInfo(
                    //   //   deviceName: '',
                    //   //   isDesiredConditionOn: 'false',
                    //   //   macAddress: scanResult.peripheral.identifier,
                    //   //   minTemper: 2,
                    //   //   maxTemper: 8,
                    //   //   minHumidity: 2,
                    //   //   maxHumidity: 8,
                    //   //   firstPath: '',
                    //   //   secondPath: '',
                    //   // ));
                    // }
                  }

                  //print(scanResult.advertisementData.manufacturerData.toString());
                  // print(scanResult.peripheral.name +
                  //     "의 advertiseData  \n"
                }
              }
              // else if (scanResult.peripheral.identifier.substring(0, 8) ==
              //     'AC:23:3F') {
              //   print('name : ' + scanResult.peripheral.name ?? '');
              //   print('id : ' + scanResult.peripheral.identifier ?? '');
              //   print('data : ' +
              //           scanResult.advertisementData.manufacturerData
              //               .toString() ??
              //       '');
              // }
            }
          }
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 01 - 07 - 08 b6 17 70 61 00 01
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 02 - 04 - 60 43 24 96
          //페이지 갱신용
          setState(() {});
        }, onError: (error) {
          print(error.toString());
          _bleManager.stopPeripheralScan();
        });
      } else {
        print('리스너 시작');
        BluetoothState tempResult = await _bleManager.bluetoothState();
        print(tempResult.toString());

        _bleManager.startPeripheralScan().listen((scanResult) {
          //listen 이벤트 형식으로 장치가 발견되면 해당 루틴을 계속 탐.
          //periphernal.name이 없으면 advertisementData.localName확인 이것도 없다면 unknown으로 표시
          print(scanResult.peripheral.name);
          var name = scanResult.peripheral.name ??
              scanResult.advertisementData.localName ??
              "Unknown";
          // 기존에 존재하는 장치면 업데이트
          // print('lenght: ' + deviceList.length.toString());
          var findDevice = deviceList.any((element) {
            if (element.peripheral.identifier ==
                scanResult.peripheral.identifier) {
              element.peripheral = scanResult.peripheral;
              element.advertisementData = scanResult.advertisementData;
              element.rssi = scanResult.rssi;

              if (currentLocation != null) {
                BleDeviceItem currentItem = new BleDeviceItem(
                    name,
                    scanResult.rssi,
                    scanResult.peripheral,
                    scanResult.advertisementData,
                    'scan');

                Data sendData = new Data(
                  battery: currentItem.getBattery().toString(),
                  deviceName:
                      'OP_' + currentItem.getDeviceId().toString().substring(7),
                  humi: currentItem.getHumidity().toString(),
                  temper: currentItem.getTemperature().toString(),
                  lat: currentLocation.latitude.toString() ?? '',
                  lng: currentLocation.longitude.toString() ?? '',
                  time: new DateTime.now().toString(),
                  lex: '',
                );
                // sendtoServer(sendData);
              }

              return true;
            }
            return false;
          });
          // 새로 발견된 장치면 추가
          if (!findDevice) {
            // if (scanResult.peripheral.identifier.substring(0, 8) == 'A4:C1:38') {
            //   print('이거임 : ' +
            //       scanResult.advertisementData.manufacturerData.toString());
            // }
            if (name != "Unknowns") {
              // print(name);
              // if (name.substring(0, 3) == 'IOT') {
              if (name != null) {
                if (name.substring(0, 4) == 'T301' ||
                    name.substring(0, 4) == 'T201' ||
                    name.substring(0, 4) == 'T306') {
                  BleDeviceItem currentItem = new BleDeviceItem(
                      name,
                      scanResult.rssi,
                      scanResult.peripheral,
                      scanResult.advertisementData,
                      'scan');
                  bool isExist = false;

                  for (int i = 0; i < savedList.length; i++) {
                    // print(savedList[i] + ' ' + currentItem.getserialNumber());
                    if (savedList[i] == currentItem.getserialNumber()) {
                      isExist = true;
                      break;
                    }
                  }

                  // print(currentItem.peripheral.identifier);
                  // print(currentItem.getserialNumber().toString());
                  // print(savedList.toString());

                  if (isExist) {
                    print('인 !');
                    print(savedList);
                    deviceList.add(currentItem);
                    // var temp
                    //     DBHelper().getDevice(scanResult.peripheral.identifier);

                    // if (temp == Null) {
                    //   print('Add ! -> ' + currentItem.getserialNumber());
                    //   // DBHelper().createData(new DeviceInfo(
                    //   //   deviceName: '',
                    //   //   isDesiredConditionOn: 'false',
                    //   //   macAddress: scanResult.peripheral.identifier,
                    //   //   minTemper: 2,
                    //   //   maxTemper: 8,
                    //   //   minHumidity: 2,
                    //   //   maxHumidity: 8,
                    //   //   firstPath: '',
                    //   //   secondPath: '',
                    //   // ));
                    // }
                  }

                  //print(scanResult.advertisementData.manufacturerData.toString());
                  // print(scanResult.peripheral.name +
                  //     "의 advertiseData  \n"
                }
              }
              // else if (scanResult.peripheral.identifier.substring(0, 8) ==
              //     'AC:23:3F') {
              //   print('name : ' + scanResult.peripheral.name ?? '');
              //   print('id : ' + scanResult.peripheral.identifier ?? '');
              //   print('data : ' +
              //           scanResult.advertisementData.manufacturerData
              //               .toString() ??
              //       '');
              // }
            }
          }
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 01 - 07 - 08 b6 17 70 61 00 01
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 02 - 04 - 60 43 24 96
          //페이지 갱신용
          setState(() {});
        });
      }
      setState(() {
        //BLE 상태가 변경되면 화면도 갱신
        _isScanning = true;
        setBLEState('<스캔중>');
      });
    } else {
      // await _bleManager.destroyClient();
      //
      // //스캔중이었으면 스캔 중지
      // // TODO: 일단 주석!
      // _bleManager.stopPeripheralScan();
      // setState(() {
      //   //BLE 상태가 변경되면 페이지도 갱신
      //   _isScanning = false;
      //   setBLEState('Stop Scan');
      // });
    }
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

  // 상태 변경하면서 페이지도 갱신하는 함수
  void setBLEState(txt) {
    setState(() => _statusText = txt);
  }

  //연결 함수
  connect(index, flag) async {
    bool goodConnection = false;
    if (_connected) {
      //이미 연결상태면 연결 해제후 종료
      await _curPeripheral?.disconnectOrCancelConnection();
      return false;
    }

    //선택한 장치의 peripheral 값을 가져온다.
    Peripheral peripheral = deviceList[index].peripheral;

    //해당 장치와의 연결상태를 관촬하는 리스너 실행
    peripheral
        .observeConnectionState(emitCurrentValue: false)
        .listen((connectionState) {
      // 연결상태가 변경되면 해당 루틴을 탐.
      print(currentState);
      switch (connectionState) {
        case PeripheralConnectionState.connected:
          {
            currentState = 'connected';
            //연결됨
            print('연결 완료 !');
            _curPeripheral = peripheral;
            // getCurrentLocation();
            //peripheral.
            deviceList[index].connectionState = 'connect';
            setBLEState('연결 완료');
            setState(() {
              processState = 3;
            });
            // startRoutine(index);
            Stream<CharacteristicWithValue> characteristicUpdates;

            print('결과 ' + characteristicUpdates.toString());

            // //데이터 받는 리스너 핸들 변수
            // StreamSubscription monitoringStreamSubscription;

            // //이미 리스너가 있다면 취소
            // //  await monitoringStreamSubscription?.cancel();
            // // ?. = 해당객체가 null이면 무시하고 넘어감.

            // monitoringStreamSubscription = characteristicUpdates.listen(
            //   (value) {
            //     print("read data : ${value.value}"); //데이터 출력
            //   },
            //   onError: (error) {
            //     print("Error while monitoring characteristic \n$error"); //실패시
            //   },
            //   cancelOnError: true, //에러 발생시 자동으로 listen 취소
            // );
            // peripheral.writeCharacteristic(BLE_SERVICE_UUID, characteristicUuid, value, withResponse)
          }
          break;
        case PeripheralConnectionState.connecting:
          {
            deviceList[index].connectionState = 'connecting';

            showMyDialog_Connecting(context);

            print('연결중입니당!');
            currentState = 'connecting';
            setBLEState('<연결 중>');
          } //연결중
          break;
        case PeripheralConnectionState.disconnected:
          {
            if (currentState == 'connecting') showMyDialog_Disconnect(context);
            //해제됨
            _connected = false;
            print("${peripheral.name} has DISCONNECTED");
            //TODO: 일단 주석 !
            // _stopMonitoringTemperature();
            deviceList[index].connectionState = 'scan';
            setBLEState('<연결 종료>');
            if (processState == 2) {
              setState(() {
                processState = 4;
              });
            }
            print('여긴 오냐');
            return false;
            //if (failFlag) {}
          }
          break;
        case PeripheralConnectionState.disconnecting:
          {
            setBLEState('<연결 종료중>');
          } //해제중
          break;
        default:
          {
            //알수없음...
            print("unkown connection state is: \n $connectionState");
          }
          break;
      }
    });

    _runWithErrorHandling(() async {
      //해당 장치와 이미 연결되어 있는지 확인
      bool isConnected = await peripheral.isConnected();
      if (isConnected) {
        print('device is already connected');
        //이미 연결되어 있기때문에 무시하고 종료..
        return this._connected;
      }

      //연결 시작!
      await peripheral
          .connect(
        isAutoConnect: false,
      )
          .then((_) {
        this._curPeripheral = peripheral;
        //연결이 되면 장치의 모든 서비스와 캐릭터리스틱을 검색한다.
        peripheral
            .discoverAllServicesAndCharacteristics()
            .then((_) => peripheral.services())
            .then((services) async {
          print("PRINTING SERVICES for ${peripheral.name}");
          //각각의 서비스의 하위 캐릭터리스틱 정보를 디버깅창에 표시한다.
          for (var service in services) {
            print("Found service ${service.uuid}");
            List<Characteristic> characteristics =
                await service.characteristics();
            for (var characteristic in characteristics) {
              print("charUUId: " + "${characteristic.uuid}");
            }
          }
          //모든 과정이 마무리되면 연결되었다고 표시

          startRoutine(index, flag);
          // if (flag == 1) {
          //   showMyDialog_finishStart(
          //       context, deviceList[index].getserialNumber());
          // }
          _connected = true;
          _isScanning = true;
          setState(() {});
        });
      });
      print(_connected.toString());
      return _connected;
    });
  }

  TextStyle lastUpdateTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 25,
      color: Color.fromRGBO(5, 5, 5, 1),
      fontWeight: FontWeight.w700,
    );
  }

  TextStyle updateTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 24,
      color: Color.fromRGBO(0xe8, 0x52, 0x55, 1),
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle boldTextStyle = TextStyle(
    fontSize: 30,
    color: Color.fromRGBO(255, 255, 255, 1),
    fontWeight: FontWeight.w700,
  );
  TextStyle bigTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 10,
      color: Color.fromRGBO(50, 50, 50, 1),
      fontWeight: FontWeight.w400,
    );
  }

  TextStyle thinTextStyle = TextStyle(
    fontSize: 22,
    color: Color.fromRGBO(244, 244, 244, 1),
    fontWeight: FontWeight.w500,
  );
  confirmPicture(
      BuildContext context, String imagePath, String flag, int index) {
    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          backgroundColor: Color.fromRGBO(235, 235, 235, 1),
          elevation: 0,
          child: Container(
              width: MediaQuery.of(context).size.width * 1.0,
              height: MediaQuery.of(context).size.height * 1.0,
              padding: EdgeInsets.all(4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        imagePath == ''
                            ? Icon(
                                Icons.camera,
                                size: MediaQuery.of(context).size.width * 0.45,
                              )
                            : flag == 'first'
                                ? Image.file(
                                    File(deviceList[index].firstPath),
                                    width: MediaQuery.of(context).size.width *
                                        0.65,
                                    height: MediaQuery.of(context).size.height *
                                        0.65,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(deviceList[index].secondPath),
                                    width: MediaQuery.of(context).size.width *
                                        0.65,
                                    height: MediaQuery.of(context).size.height *
                                        0.65,
                                    fit: BoxFit.cover,
                                  )
                      ],
                    ),
                  ),
                  Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: Container(
                                      margin: EdgeInsets.only(
                                        top: 12,
                                      ),
                                      // padding:
                                      //     EdgeInsets.only(top: 0, left: 12),
                                      height: 50,
                                      width: MediaQuery.of(context).size.width *
                                          0.3,
                                      decoration: BoxDecoration(
                                          color: Color.fromRGBO(
                                              0x61, 0xB2, 0xD0, 1),
                                          //boxShadow: [customeBoxShadow()],
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(5))),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text('취소',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 28,
                                                    fontWeight:
                                                        FontWeight.bold))
                                          ]))),
                              TextButton(
                                  onPressed: () {
                                    if (flag == 'first') {
                                      takePicture(context, index);

                                      Navigator.of(context).pop();
                                    } else if (flag == 'second') {
                                      takePicture2(context, index);
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: Container(
                                      margin: EdgeInsets.only(
                                        top: 12,
                                      ),
                                      // padding:
                                      //     EdgeInsets.only(top: 0, left: 12),
                                      height: 50,
                                      width: MediaQuery.of(context).size.width *
                                          0.3,
                                      decoration: BoxDecoration(
                                          color: Color.fromRGBO(
                                              0x61, 0xB2, 0xD0, 1),
                                          //boxShadow: [customeBoxShadow()],
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(5))),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              '재촬영',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold),
                                            )
                                          ]))),
                            ],
                          ),
                          flag == 'second'
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                        onPressed: () async {
                                          await connect(index, 0);
                                        },
                                        child: Container(
                                            height: 50,
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.68,
                                            decoration: BoxDecoration(
                                                color: Color.fromRGBO(
                                                    0x61, 0xB2, 0xD0, 1),
                                                //boxShadow: [customeBoxShadow()],
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(5))),
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '운송완료',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 28,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  )
                                                ]))),
                                  ],
                                )
                              : SizedBox(),
                          flag == 'first'
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                        onPressed: () async {
                                          await connect(index, 1);
                                          // startTransportDialog(context, index);
                                        },
                                        child: Container(
                                            height: 50,
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.68,
                                            decoration: BoxDecoration(
                                                color: Color.fromRGBO(
                                                    0x61, 0xB2, 0xD0, 1),
                                                //boxShadow: [customeBoxShadow()],
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(5))),
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '운송시작',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 28,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  )
                                                ]))),
                                  ],
                                )
                              : SizedBox()
                        ],
                      ))
                ],
              )),
        );
      },
    );
  }
  // confirmPicture(
  //     BuildContext context, String imagePath, String flag, int index) {
  //   return showDialog(
  //       barrierDismissible: false,
  //       context: context,
  //       builder: (context) {
  //         return Dialog(
  //           shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(20.0)),
  //           backgroundColor: Color.fromRGBO(235, 235, 235, 1),
  //           elevation: 0,
  //           child: Container(
  //               width: MediaQuery.of(context).size.width * 1.0,
  //               height: MediaQuery.of(context).size.height * 1.0,
  //               padding: EdgeInsets.all(4.0),
  //               child: Column(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   Expanded(
  //                     flex: 4,
  //                     child: Column(
  //                       mainAxisAlignment: MainAxisAlignment.center,
  //                       children: [
  //                         imagePath == ''
  //                             ? Icon(
  //                                 Icons.camera,
  //                                 size:
  //                                     MediaQuery.of(context).size.width * 0.45,
  //                               )
  //                             : flag == 'first'
  //                                 ? Image.file(
  //                                     File(deviceList[index].firstPath),
  //                                     width: MediaQuery.of(context).size.width *
  //                                         0.65,
  //                                     height:
  //                                         MediaQuery.of(context).size.height *
  //                                             0.65,
  //                                     fit: BoxFit.cover,
  //                                   )
  //                                 : Image.file(
  //                                     File(deviceList[index].secondPath),
  //                                     width: MediaQuery.of(context).size.width *
  //                                         0.65,
  //                                     height:
  //                                         MediaQuery.of(context).size.height *
  //                                             0.65,
  //                                     fit: BoxFit.cover,
  //                                   )
  //                       ],
  //                     ),
  //                   ),
  //                   Expanded(
  //                       flex: 1,
  //                       child: Column(
  //                         children: [
  //                           Row(
  //                             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  //                             children: [
  //                               TextButton(
  //                                   onPressed: () {
  //                                     Navigator.of(context).pop();
  //                                   },
  //                                   child: Container(
  //                                       margin: EdgeInsets.only(
  //                                         top: 12,
  //                                       ),
  //                                       // padding:
  //                                       //     EdgeInsets.only(top: 0, left: 12),
  //                                       height: 50,
  //                                       width:
  //                                           MediaQuery.of(context).size.width *
  //                                               0.3,
  //                                       decoration: BoxDecoration(
  //                                           color: Color.fromRGBO(
  //                                               0x61, 0xB2, 0xD0, 1),
  //                                           //boxShadow: [customeBoxShadow()],
  //                                           borderRadius: BorderRadius.all(
  //                                               Radius.circular(5))),
  //                                       child: Column(
  //                                           mainAxisAlignment:
  //                                               MainAxisAlignment.center,
  //                                           crossAxisAlignment:
  //                                               CrossAxisAlignment.center,
  //                                           children: [
  //                                             Text('취소',
  //                                                 style: TextStyle(
  //                                                     color: Colors.white,
  //                                                     fontSize: 28,
  //                                                     fontWeight:
  //                                                         FontWeight.bold))
  //                                           ]))),
  //                               TextButton(
  //                                   onPressed: () async {
  //                                     if (flag == 'first') {
  //                                       String temp =
  //                                           await takePicture(context, index);
  //                                       print(temp);
  //                                       if (temp != '' && temp != null) {
  //                                         deviceList[index].firstPath = temp;
  //                                         setState(() {
  //                                           deviceList[index].firstPath = temp;
  //                                         });
  //                                       }

  //                                       // Navigator.of(context).pop(temp);
  //                                     } else if (flag == 'second') {
  //                                       String temp =
  //                                           await takePicture2(context, index);
  //                                       if (temp != '' && temp != null) {
  //                                         deviceList[index].secondPath = temp;
  //                                         setState(() {
  //                                           deviceList[index].secondPath = temp;
  //                                         });
  //                                       }
  //                                       // Navigator.of(context).pop(temp);
  //                                     }
  //                                   },
  //                                   child: Container(
  //                                       margin: EdgeInsets.only(
  //                                         top: 12,
  //                                       ),
  //                                       // padding:
  //                                       //     EdgeInsets.only(top: 0, left: 12),
  //                                       height: 50,
  //                                       width:
  //                                           MediaQuery.of(context).size.width *
  //                                               0.3,
  //                                       decoration: BoxDecoration(
  //                                           color: Color.fromRGBO(
  //                                               0x61, 0xB2, 0xD0, 1),
  //                                           //boxShadow: [customeBoxShadow()],
  //                                           borderRadius: BorderRadius.all(
  //                                               Radius.circular(5))),
  //                                       child: Column(
  //                                           mainAxisAlignment:
  //                                               MainAxisAlignment.center,
  //                                           crossAxisAlignment:
  //                                               CrossAxisAlignment.center,
  //                                           children: [
  //                                             Text(
  //                                               '재촬영',
  //                                               style: TextStyle(
  //                                                   color: Colors.white,
  //                                                   fontSize: 28,
  //                                                   fontWeight:
  //                                                       FontWeight.bold),
  //                                             )
  //                                           ]))),
  //                             ],
  //                           ),
  //                           flag == 'second'
  //                               ? Row(
  //                                   mainAxisAlignment: MainAxisAlignment.center,
  //                                   children: [
  //                                     TextButton(
  //                                         onPressed: () async {
  //                                           await connect(index, 0);
  //                                         },
  //                                         child: Container(
  //                                             height: 50,
  //                                             width: MediaQuery.of(context)
  //                                                     .size
  //                                                     .width *
  //                                                 0.68,
  //                                             decoration: BoxDecoration(
  //                                                 color: Color.fromRGBO(
  //                                                     0x61, 0xB2, 0xD0, 1),
  //                                                 //boxShadow: [customeBoxShadow()],
  //                                                 borderRadius:
  //                                                     BorderRadius.all(
  //                                                         Radius.circular(5))),
  //                                             child: Column(
  //                                                 mainAxisAlignment:
  //                                                     MainAxisAlignment.center,
  //                                                 crossAxisAlignment:
  //                                                     CrossAxisAlignment.center,
  //                                                 children: [
  //                                                   Text(
  //                                                     '운송완료',
  //                                                     style: TextStyle(
  //                                                         color: Colors.white,
  //                                                         fontSize: 28,
  //                                                         fontWeight:
  //                                                             FontWeight.bold),
  //                                                   )
  //                                                 ]))),
  //                                   ],
  //                                 )
  //                               : SizedBox(),
  //                           flag == 'first'
  //                               ? Row(
  //                                   mainAxisAlignment: MainAxisAlignment.center,
  //                                   children: [
  //                                     TextButton(
  //                                         onPressed: () async {
  //                                           await connect(index, 1);
  //                                           // startTransportDialog(context, index);
  //                                         },
  //                                         child: Container(
  //                                             height: 50,
  //                                             width: MediaQuery.of(context)
  //                                                     .size
  //                                                     .width *
  //                                                 0.68,
  //                                             decoration: BoxDecoration(
  //                                                 color: Color.fromRGBO(
  //                                                     0x61, 0xB2, 0xD0, 1),
  //                                                 //boxShadow: [customeBoxShadow()],
  //                                                 borderRadius:
  //                                                     BorderRadius.all(
  //                                                         Radius.circular(5))),
  //                                             child: Column(
  //                                                 mainAxisAlignment:
  //                                                     MainAxisAlignment.center,
  //                                                 crossAxisAlignment:
  //                                                     CrossAxisAlignment.center,
  //                                                 children: [
  //                                                   Text(
  //                                                     '운송시작',
  //                                                     style: TextStyle(
  //                                                         color: Colors.white,
  //                                                         fontSize: 28,
  //                                                         fontWeight:
  //                                                             FontWeight.bold),
  //                                                   )
  //                                                 ]))),
  //                                   ],
  //                                 )
  //                               : SizedBox()
  //                         ],
  //                       ))
  //                 ],
  //               )),
  //         );
  //       });
  // }

  Future<void> addDeviceDialog(BuildContext context) async {
    String valueText = '';
    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('디바이스 추가'),
            content: TextField(
              onChanged: (value) {
                setState(() {
                  valueText = value;
                });
              },
              controller: _textFieldController,
              decoration: InputDecoration(hintText: 'Mac 주소를 입력해주세요'),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('취소'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context);
                  });
                },
              ),
              TextButton(
                  child: Text('등록'),
                  onPressed: () async {
                    String temp = valueText.toUpperCase();
                    if (temp.length != 6) {
                      showMyDialog_Error(context);
                    } else {
                      await DBHelper().createSavedMac(temp);
                      // print('길이몇인데 ? ' + valueText.length.toString());
                      if (valueText.length == 6) {
                        // print('valueText: ' + temp);
                        await DBHelper().createData(new DeviceInfo(
                          deviceName: '',
                          isDesiredConditionOn: 'false',
                          macAddress: temp,
                          minTemper: 4,
                          maxTemper: 28,
                          minHumidity: 2,
                          maxHumidity: 8,
                          firstPath: '',
                          secondPath: '',
                        ));
                        // print(temp.substring(0, 2) +
                        //     ":" +
                        //     temp.substring(2, 4) +
                        //     ':' +
                        //     temp.substring(4, 6));
                        setState(() {
                          savedList.add(temp);
                        });

                        await showMyDialog_finishAdd(context, temp);
                      }

                      Navigator.pop(context);
                    }
                    // print(savedList);
                  }),
            ],
          );
        });
  }

  Future<void> startTransportDialog(BuildContext context, int index) async {
    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('운송시작'),
            content: Text('기존 데이터가 삭제됩니다.\n운송을 시작하시겠습니까?'),
            actions: <Widget>[
              TextButton(
                  child: Text('시작하기'),
                  onPressed: () async {
                    var result = await connect(index, 1);
                    print('설마');
                    print(result.toString());
                    Navigator.pop(context);
                    // print(savedList);
                  }),
              TextButton(
                child: Text('취소'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context);
                  });
                },
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
          appBar: AppBar(
              // backgroundColor: Color.fromARGB(22, 27, 32, 1),
              title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 8,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(
                    'Thermo Cert',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width / 18,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              Expanded(
                  flex: 4,
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    new IconButton(
                      icon: new Icon(Icons.add, size: 30),
                      onPressed: () {
                        addDeviceDialog(context);
                      },
                    )
                  ])),
            ],
          )),
          body: Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Color.fromRGBO(240, 240, 240, 1),
              boxShadow: [customeBoxShadow()],
              //color: Color.fromRGBO(81, 97, 130, 1),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                    flex: 6,
                    child: Container(
                      margin: EdgeInsets.only(
                          top: MediaQuery.of(context).size.width * 0.035),
                      width: MediaQuery.of(context).size.width * 0.97,
                      // height:
                      //     MediaQuery.of(context).size.width * 0.45,

                      child: list2(),
                    ) //리스트 출력
                    ),
              ],
            ),
          ),
        ));
  }

  BoxShadow customeBoxShadow() {
    return BoxShadow(
        color: Colors.black.withOpacity(0.2),
        offset: Offset(0, 1),
        blurRadius: 6);
  }

  Widget getbatteryImage(int battery) {
    if (battery >= 75) {
      return Image(
        image: AssetImage('images/battery_100.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.1,
        height: MediaQuery.of(context).size.width * 0.1,
      );
    } else if (battery >= 50) {
      return Image(
        image: AssetImage('images/battery_75.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.1,
        height: MediaQuery.of(context).size.width * 0.1,
      );
    } else if (battery >= 35) {
      return Image(
        image: AssetImage('images/battery_50.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.05,
        height: MediaQuery.of(context).size.width * 0.05,
      );
    } else {
      return Image(
        image: AssetImage('images/battery_25.png'),
        fit: BoxFit.contain,
        width: MediaQuery.of(context).size.width * 0.1,
        height: MediaQuery.of(context).size.width * 0.1,
      );
    }
  }

  TextStyle whiteTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 18,
      color: Color.fromRGBO(255, 255, 255, 1),
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle btnTextStyle = TextStyle(
    fontSize: 20,
    color: Color.fromRGBO(255, 255, 255, 1),
    fontWeight: FontWeight.w700,
  );

  Uint8List stringToBytes(String source) {
    var list = new List<int>();
    source.runes.forEach((rune) {
      if (rune >= 0x10000) {
        rune -= 0x10000;
        int firstWord = (rune >> 10) + 0xD800;
        list.add(firstWord >> 8);
        list.add(firstWord & 0xFF);
        int secondWord = (rune & 0x3FF) + 0xDC00;
        list.add(secondWord >> 8);
        list.add(secondWord & 0xFF);
      } else {
        list.add(rune >> 8);
        list.add(rune & 0xFF);
      }
    });
    return Uint8List.fromList(list);
  }

  String bytesToString(Uint8List bytes) {
    StringBuffer buffer = new StringBuffer();
    for (int i = 0; i < bytes.length;) {
      int firstWord = (bytes[i] << 8) + bytes[i + 1];
      if (0xD800 <= firstWord && firstWord <= 0xDBFF) {
        int secondWord = (bytes[i + 2] << 8) + bytes[i + 3];
        buffer.writeCharCode(
            ((firstWord - 0xD800) << 10) + (secondWord - 0xDC00) + 0x10000);
        i += 4;
      } else {
        buffer.writeCharCode(firstWord);
        i += 2;
      }
    }
    return buffer.toString();
  }

  _checkPermissionCamera() async {
    if (await Permission.camera.request().isGranted) {
      scan();
      return '';
    }
    Map<Permission, PermissionStatus> statuses =
        await [Permission.camera, Permission.storage].request();
    //print("여기는요?" + statuses[Permission.location].toString());
    if (statuses[Permission.camera].toString() == "PermissionStatus.granted" &&
        statuses[Permission.storage].toString() == 'PermissionStatus.granted') {
      scan();
      return 'Pass';
    }
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
}

showMyDialog_Disconnect(BuildContext context) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 1)).then((_) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
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
                      Text("재연결이 필요합니다.",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
                          textAlign: TextAlign.center),
                      Text("다시 시도해 주세요 !",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
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

showMyDialog_Error(BuildContext context) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        // elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 3.5,
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
                      Text("잘못 입력되었습니다. \n다시 입력해주세요.",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
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

showMyDialog_finishAdd(BuildContext context, String deviceName) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 3)).then((_) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        // elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 3.5,
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
                        Icons.check_box,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text(deviceName,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 20)),
                      Text("등록이 완료되었습니다.",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
                          textAlign: TextAlign.center),
                      Text("리스트에 추가 중 입니다.\n최대 1분의 시간이 소요됩니다. ",
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

showMyDialog_finishStart(BuildContext context, String deviceName) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        // elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 3.5,
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
                        Icons.check_box,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text(deviceName,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 20)),
                      Text("운송이 시작되었습니다. ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
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

showMyDialog_Connecting(BuildContext context) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
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
                        Icons.bluetooth,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text("데이터 전송을 시작합니다 !",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
                          textAlign: TextAlign.center),
                      Text("로딩이 되지 않으면 다시 눌러주세요.",
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

showMyDialog_StartTransport(BuildContext context) {
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
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
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
                        Icons.check_box,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text("운송을 시작합니다. ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 20),
                          textAlign: TextAlign.center),
                      // Text("안전한 운행되세요.",
                      //     style: TextStyle(
                      //         color: Colors.white,
                      //         fontWeight: FontWeight.w600,
                      //         fontSize: 14),
                      //     textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}
