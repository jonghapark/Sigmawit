import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

final String TableName = 'DeviceInfo';

class DeviceInfo {
  List<LogData> logDatas;
  String deviceName;
  String macAddress;
  String isDesiredConditionOn;
  int minTemper;
  int maxTemper;
  int minHumidity;
  int maxHumidity;
  String firstPath;
  String secondPath;
  DeviceInfo(
      {this.deviceName,
      this.isDesiredConditionOn,
      this.macAddress,
      this.maxHumidity,
      this.maxTemper,
      this.minHumidity,
      this.minTemper,
      this.firstPath,
      this.secondPath});
}

class LogData {
  double temperature;
  double humidity;
  DateTime timestamp;
  LogData({this.humidity, this.temperature, this.timestamp});
}

class DBHelper {
  DBHelper._();
  static final DBHelper _db = DBHelper._();
  factory DBHelper() => _db;

  static Database _database;

  Future<Database> get database async {
    if (_database != null) return _database;

    _database = await initDB();
    return _database;
  }

  initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'DeviceInfo3.db');

    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
          CREATE TABLE $TableName(
            id INTEGER PRIMARY KEY,
            name TEXT,
            mac TEXT,
            conditionflag TEXT,
            minTemp INTEGER,
            maxTemp INTEGER,
            minHumi INTEGER,
            maxHumi INTEGER,
            firstPath TEXT,
            secondPath TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE savedList(
            id INTEGER PRIMARY KEY,
            mac TEXT
          )
        ''');
    }, onUpgrade: (db, oldVersion, newVersion) {});
  }

  //Create
  createData(DeviceInfo device) async {
    final db = await database;
    // print(device.macAddress);
    var res = await db.rawInsert(
        'INSERT INTO $TableName(name, mac, conditionflag, minTemp, maxTemp, minHumi , maxHumi, firstPath, secondPath) VALUES(?,?,?,?,?,?,?,?,?)',
        [device.deviceName, device.macAddress, 'false', 0, 0, 0, 0, '', '']);
    return res;
  }

  //Create
  createSavedMac(String mac) async {
    print(mac.toUpperCase());
    final db = await database;
    var res = await db
        .rawInsert('INSERT INTO savedList(mac) VALUES(?)', [mac.toUpperCase()]);
    return res;
  }

  //Read
  getDevice(String macAddress) async {
    final db = await database;
    print('이거 검색함 ' + macAddress.toUpperCase());
    var res = await db.rawQuery(
        'SELECT * FROM $TableName WHERE mac = ?', [macAddress.toUpperCase()]);
    return res.isNotEmpty
        ? DeviceInfo(
            macAddress: res.first['mac'],
            deviceName: res.first['name'],
            isDesiredConditionOn: res.first['conditionflag'],
            minTemper: res.first['minTemp'],
            maxTemper: res.first['maxTemp'],
            minHumidity: res.first['minHumi'],
            maxHumidity: res.first['maxHumi'],
            firstPath: res.first['firstPath'],
            secondPath: res.first['secondPath'])
        : Null;
  }

  //Update-name
  updateDeviceName(String macAddress, String newName) async {
    final db = await database;
    var res = await db.rawUpdate('UPDATE $TableName SET name = ? WHERE mac = ?',
        [newName, macAddress.toUpperCase()]);
  }

  //Update-imagePath
  updateImagePath(String macAddress, String path, String flag) async {
    final db = await database;
    if (flag == 'first') {
      var res = await db.rawUpdate(
          'UPDATE $TableName SET firstPath = ?, secondPath = ? WHERE mac = ?',
          [path, '', macAddress]);
    } else if (flag == 'second') {
      var res = await db.rawUpdate(
          'UPDATE $TableName SET secondPath = ? WHERE mac = ?',
          [path, macAddress]);
    }
  }

  //Update-name
  updateDeviceCondition(String macAddress, int minTemp, int maxTemp,
      int minHumi, int maxHumi, String conditionFlag) async {
    final db = await database;
    var res = await db.rawUpdate(
        'UPDATE $TableName SET minTemp = ?, maxTemp = ?, minHumi = ?, maxHumi = ?, conditionflag = ? WHERE mac = ?',
        [minTemp, maxTemp, minHumi, maxHumi, conditionFlag, macAddress]);
  }

  //reset-Device
  resetDevice(String macAddress) async {
    final db = await database;
    var res = await db.rawUpdate(
        'UPDATE $TableName SET firstPath = ?, secondPath = ? WHERE mac = ?',
        ['', '', macAddress]);
  }

  //Read All
  Future<List<DeviceInfo>> getAllDevices() async {
    final db = await database;
    var res = await db.rawQuery('SELECT * FROM $TableName');
    List<DeviceInfo> list = res.isNotEmpty
        ? res
            .map((c) => DeviceInfo(
                macAddress: c['mac'],
                deviceName: c['name'],
                isDesiredConditionOn: c['conditionflag'],
                minTemper: c['minTemp'],
                maxTemper: c['maxTemp'],
                minHumidity: c['minHumi'],
                maxHumidity: c['maxHumi'],
                firstPath: c['firstPath'],
                secondPath: c['secondPath']))
            .toList()
        : [];
    // print(list[0].macAddress);
    return list;
  }

  //Read All
  Future<List<String>> getAllSavedList() async {
    final db = await database;
    var res = await db.rawQuery('SELECT * FROM savedList');
    print('저장 데이터 읽기 시작');
    List<String> list =
        res.isNotEmpty ? res.map((c) => c['mac'].toString()).toList() : [];
    print(list);
    return list;
  }

  //Delete
  deleteDevice(String macAddress) async {
    final db = await database;
    var res =
        db.rawDelete('DELETE FROM $TableName WHERE mac = ?', [macAddress]);
    print('DeleteDevice');
    return res;
  }

  //Delete
  deleteSavedDevice(String mac) async {
    // print(mac);
    final db = await database;
    var res = db.rawDelete('DELETE FROM savedList WHERE mac = ?', [mac]);
    print('DeleteSavedDevice');
    return res;
  }

  //Delete All
  deleteAllDevices() async {
    final db = await database;
    db.rawDelete('DELETE FROM $TableName');
  }
}
