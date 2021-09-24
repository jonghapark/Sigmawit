import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'dart:typed_data';
import 'dart:convert';

//BLE 장치 정보 저장 클래스
class BleDeviceItem {
  bool sendState = true;
  DateTime lastUpdateTime;
  String deviceName;
  Peripheral peripheral;
  int rssi;
  AdvertisementData advertisementData;
  String connectionState;
  String firstPath = '';
  String secondPath = '';
  BleDeviceItem(this.deviceName, this.rssi, this.peripheral,
      this.advertisementData, this.connectionState);

  getTemperature() {
    int tmp = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(12, 14))
        .getInt16(0, Endian.big);
    // print(tmp);
    lastUpdateTime = DateTime.now();
    return tmp / 100;
  }

  getHumidity() {
    int tmp = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(14, 16))
        .getInt16(0, Endian.big);
    // print(tmp);
    return tmp / 100;
  }

  getBattery() {
    int tmp = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(16, 17))
        .getInt8(0);
    return tmp;
  }

  getDeviceId() {
    if (this.deviceName == 'T301' || this.deviceName == 'T306') {
      String tmpString = this.getserialNumber();
      String tmp = ByteData.sublistView(
              this.advertisementData.manufacturerData.sublist(7, 9))
          .getUint16(0)
          .toString();
      String tmp2 = ByteData.sublistView(
              this.advertisementData.manufacturerData.sublist(9, 10))
          .getUint8(0)
          .toString();
      int tmps = int.parse(tmp);
      int tmps2 = int.parse(tmp2);
      String result = tmps.toRadixString(16);
      if (tmps2 < 10) {
        result += '0' + tmps2.toRadixString(16);
      } else {
        result += tmps2.toRadixString(16);
      }
      return 'Sensor_' + tmpString;
    } else {
      return this.deviceName;
    }
  }

  String getserialNumber() {
    String tmp = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(7, 8))
        .getUint8(0)
        .toString();
    String tmp2 = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(8, 9))
        .getUint8(0)
        .toString();
    String tmp3 = ByteData.sublistView(
            this.advertisementData.manufacturerData.sublist(9, 10))
        .getUint8(0)
        .toString();
    int tmps = int.parse(tmp);
    int tmps2 = int.parse(tmp2);
    int tmps3 = int.parse(tmp3);
    String result = '';

    if (tmps < 16) {
      result += '0' + tmps.toRadixString(16);
    } else {
      result += tmps.toRadixString(16);
    }
    if (tmps2 < 16) {
      result += '0' + tmps2.toRadixString(16);
    } else {
      result += tmps2.toRadixString(16);
    }
    if (tmps3 < 16) {
      result += '0' + tmps3.toRadixString(16);
    } else {
      result += tmps3.toRadixString(16);
    }
    // print(result.length.toString());
    return result.toUpperCase();
  }

  getMacAddress() {
    print('3' + this.advertisementData.manufacturerData.toString());
    Uint8List macAddress =
        this.advertisementData.manufacturerData.sublist(4, 10);
    return macAddress;
  }
}

class Data {
  String lat;
  String lng;
  String deviceName;
  String temper;
  String humi;
  String time;
  String battery;
  String lex;

  Data(
      {this.deviceName,
      this.humi,
      this.lat,
      this.lng,
      this.temper,
      this.time,
      this.lex,
      this.battery});
}
