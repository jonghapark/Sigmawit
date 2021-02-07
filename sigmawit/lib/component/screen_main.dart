import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/model_bleDevice.dart';
import '../utils/util.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:location/location.dart' as loc;
import 'package:geocoder/geocoder.dart';
import 'package:intl/intl.dart';
import 'package:toggle_switch/toggle_switch.dart';

// URL
// 10.3.141.1:4000

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
  //List<BleDeviceItem> myDeviceList = [];
  String _statusText = ''; // BLE 상태 변수
  loc.LocationData currentLocation;
  int dataSize = 0;
  loc.Location location = new loc.Location();
  int processState = 1;
  StreamSubscription<loc.LocationData> _locationSubscription;
  String _error;
  String geolocation;
  String currentDeviceName = '';
  // double width;

  String currentTemp;
  String currentHumi;

  @override
  void initState() {
    super.initState();
    //width = MediaQuery.of(context).size.width;
    currentDeviceName = '';
    currentTemp = '-';
    currentHumi = '-';
    _listenLocation();
    // getCurrentLocation();
    init();
    // location.onLocationChanged.listen((loc.LocationData currentLocation) {
    //   this.currentLocation = currentLocation;
    //   print('여긴오냐 ->' + currentLocation.latitude.toString());
    //   // Use current location
    // });
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
      if (!_isScanning) {
        scan();
      }
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
    await _bleManager
        .createClient(
            restoreStateIdentifier: "example-restore-state-identifier",
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
      if (await Permission.contacts.request().isGranted) {
        print('입장하냐?');
        scan();
        return;
      }
      Map<Permission, PermissionStatus> statuses =
          await [Permission.location].request();
      print("여기는요?" + statuses[Permission.location].toString());
      if (statuses[Permission.location].toString() ==
          "PermissionStatus.granted") {
        //getCurrentLocation();
        scan();
      }
    }
  }

  //장치 화면에 출력하는 위젯 함수
  list() {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: deviceList.length,
      itemBuilder: (BuildContext context, int index) {
        return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              //boxShadow: [customeBoxShadow()],
              borderRadius: BorderRadius.all(Radius.circular(5))),
          height: MediaQuery.of(context).size.height * 0.3,
          width: MediaQuery.of(context).size.width * 0.98,
          child: Column(children: [
            Expanded(
              flex: 3,
              child: Container(
                  width: MediaQuery.of(context).size.width * 0.98,
                  decoration: BoxDecoration(
                      color: Color.fromRGBO(71, 71, 71, 1),
                      //boxShadow: [customeBoxShadow()],
                      borderRadius: BorderRadius.all(Radius.circular(5))),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceList[index].getDeviceId(),
                        style: whiteTextStyle,
                      ),
                      Text(
                        deviceList[index].getBattery().toString(),
                        style: whiteTextStyle,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ToggleSwitch(
                            // initialLabelIndex:
                            //     deviceList[index].sendState == true ||
                            //             deviceList[index].sendState == null
                            //         ? 0
                            //         : 1,
                            minWidth: 100.0,
                            cornerRadius: 20.0,
                            activeBgColor: Colors.cyan,
                            activeFgColor: Colors.white,
                            inactiveBgColor: Colors.grey,
                            inactiveFgColor: Colors.white,
                            labels: ['ON', 'OFF'],
                            icons: [Icons.check, Icons.highlight_off],
                            onToggle: (index) async {
                              if (index == 0) {
                                deviceList[index].sendState = true;
                                setState(() {});
                              } else {
                                deviceList[index].sendState = false;
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      )
                    ],
                  )),
            ),
            Expanded(
                flex: 3,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Row(
                            children: [
                              Image(
                                image: AssetImage('images/ic_thermometer.png'),
                                fit: BoxFit.cover,
                                width: MediaQuery.of(context).size.width * 0.10,
                                height:
                                    MediaQuery.of(context).size.width * 0.10,
                              ),
                              Text(
                                  deviceList[index]
                                          .getTemperature()
                                          .toString() +
                                      '°C',
                                  style: bigTextStyle),
                            ],
                          ),
                          Row(
                            children: [
                              Image(
                                image: AssetImage('images/ic_humidity.png'),
                                fit: BoxFit.cover,
                                width: MediaQuery.of(context).size.width * 0.09,
                                height:
                                    MediaQuery.of(context).size.width * 0.09,
                              ),
                              Text(
                                deviceList[index].getHumidity().toString() +
                                    '%',
                                style: bigTextStyle,
                              )
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Last updated  '),
                          deviceList[index].lastUpdateTime != null
                              ? Text(
                                  DateFormat('yyyy-MM-dd - HH:mm')
                                      .format(deviceList[index].lastUpdateTime),
                                  style: updateTextStyle,
                                )
                              : Text(
                                  '-',
                                  style: updateTextStyle,
                                ),
                        ],
                      )
                    ]))
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

  //scan 함수
  void scan() async {
    if (!_isScanning) {
      deviceList.clear(); //기존 장치 리스트 초기화
      //SCAN 시작
      _bleManager.startPeripheralScan().listen((scanResult) {
        //listen 이벤트 형식으로 장치가 발견되면 해당 루틴을 계속 탐.
        //periphernal.name이 없으면 advertisementData.localName확인 이것도 없다면 unknown으로 표시
        //print(scanResult.peripheral.name);
        var name = scanResult.peripheral.name ??
            scanResult.advertisementData.localName ??
            "Unknown";
        // 기존에 존재하는 장치면 업데이트
        var findDevice = deviceList.any((element) {
          if (element.peripheral.identifier ==
              scanResult.peripheral.identifier) {
            element.peripheral = scanResult.peripheral;
            element.advertisementData = scanResult.advertisementData;
            element.rssi = scanResult.rssi;
            return true;
          }
          return false;
        });
        // 새로 발견된 장치면 추가
        if (!findDevice) {
          if (name != "Unknown") {
            // if (name.substring(0, 3) == 'IOT') {

            if (name.substring(0, 4) == 'T301')
              deviceList.add(BleDeviceItem(name, scanResult.rssi,
                  scanResult.peripheral, scanResult.advertisementData));
            // print(scanResult.peripheral.name +
            //     "의 advertiseData  \n" +
            // }
          }
        }
        //페이지 갱신용
        setState(() {});
      });
      setState(() {
        //BLE 상태가 변경되면 화면도 갱신
        _isScanning = true;
        setBLEState('<스캔중>');
      });
    } else {
      //스캔중이었으면 스캔 중지
      // TODO: 일단 주석!
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
  connect(index) async {
    if (_connected) {
      //이미 연결상태면 연결 해제후 종료
      await _curPeripheral?.disconnectOrCancelConnection();
      return;
    }

    //선택한 장치의 peripheral 값을 가져온다.
    Peripheral peripheral = deviceList[index].peripheral;

    //해당 장치와의 연결상태를 관촬하는 리스너 실행
    peripheral
        .observeConnectionState(emitCurrentValue: false)
        .listen((connectionState) {
      // 연결상태가 변경되면 해당 루틴을 탐.
      switch (connectionState) {
        case PeripheralConnectionState.connected:
          {
            //연결됨
            _curPeripheral = peripheral;
            getCurrentLocation();
            //peripheral.
            setBLEState('연결 완료');
            setState(() {
              processState = 3;
            });
            Stream<CharacteristicWithValue> characteristicUpdates;

            print('결과 ' + characteristicUpdates.toString());

            //데이터 받는 리스너 핸들 변수
            StreamSubscription monitoringStreamSubscription;

            //이미 리스너가 있다면 취소
            //  await monitoringStreamSubscription?.cancel();
            // ?. = 해당객체가 null이면 무시하고 넘어감.

            monitoringStreamSubscription = characteristicUpdates.listen(
              (value) {
                print("read data : ${value.value}"); //데이터 출력
              },
              onError: (error) {
                print("Error while monitoring characteristic \n$error"); //실패시
              },
              cancelOnError: true, //에러 발생시 자동으로 listen 취소
            );
            // peripheral.writeCharacteristic(BLE_SERVICE_UUID, characteristicUuid, value, withResponse)
          }
          break;
        case PeripheralConnectionState.connecting:
          {
            print('연결중입니당!');
            setBLEState('<연결 중>');
          } //연결중
          break;
        case PeripheralConnectionState.disconnected:
          {
            //해제됨
            _connected = false;
            print("${peripheral.name} has DISCONNECTED");
            setBLEState('<연결 종료>');
            if (processState == 2) {
              setState(() {
                processState = 4;
              });
            }
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
          .connect(isAutoConnect: true, refreshGatt: true)
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
          _connected = true;
          _isScanning = true;
          setState(() {});
        });
      });
      return _connected;
    });
  }

  TextStyle updateTextStyle = TextStyle(
    fontSize: 15,
    color: Color.fromRGBO(0xe8, 0x52, 0x55, 1),
    fontWeight: FontWeight.w300,
  );
  TextStyle boldTextStyle = TextStyle(
    fontSize: 30,
    color: Color.fromRGBO(255, 255, 255, 1),
    fontWeight: FontWeight.w700,
  );

  TextStyle bigTextStyle = TextStyle(
    fontSize: 35,
    color: Color.fromRGBO(150, 150, 150, 1),
    fontWeight: FontWeight.w400,
  );

  TextStyle thinTextStyle = TextStyle(
    fontSize: 22,
    color: Color.fromRGBO(244, 244, 244, 1),
    fontWeight: FontWeight.w500,
  );
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Sigmawit',
        theme: ThemeData(
          // primarySwatch: Colors.grey,
          primaryColor: Color.fromRGBO(22, 33, 55, 1),
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
                'Orior',
                textAlign: TextAlign.center,
              ),
            ],
          )),
          body: Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Color.fromRGBO(240, 240, 240, 1),
              //boxShadow: [customeBoxShadow()],
              //color: Color.fromRGBO(81, 97, 130, 1),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                    flex: 6,
                    child: Container(
                      margin: EdgeInsets.all(
                          MediaQuery.of(context).size.width * 0.035),
                      width: MediaQuery.of(context).size.width * 0.915,
                      // height:
                      //     MediaQuery.of(context).size.width * 0.45,

                      child: list(),
                    ) //리스트 출력
                    ),
              ],
            ),
          ),
        ));
  }

  BoxShadow customeBoxShadow() {
    return BoxShadow(
        color: Colors.black.withOpacity(0.5),
        offset: Offset(0, 5),
        blurRadius: 6);
  }

  TextStyle whiteTextStyle = TextStyle(
    fontSize: 18,
    color: Color.fromRGBO(255, 255, 255, 1),
    fontWeight: FontWeight.w300,
  );
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
    if (Platform.isAndroid) {
      if (await Permission.contacts.request().isGranted) {
        print('입장하냐?');
        //scan();
        return '';
      }
      Map<Permission, PermissionStatus> statuses =
          await [Permission.camera, Permission.storage].request();
      //print("여기는요?" + statuses[Permission.location].toString());
      if (statuses[Permission.camera].toString() ==
              "PermissionStatus.granted" &&
          statuses[Permission.storage].toString() ==
              'PermissionStatus.granted') {
        return 'Pass';
      }
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
    print('서비스는사용가능? ');
    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }
    print('위치받는중? ');
    _locationData = await location.getLocation();
    print('lat: ' + _locationData.latitude.toString());
    setState(() {
      currentLocation = _locationData;
    });
  }
}
