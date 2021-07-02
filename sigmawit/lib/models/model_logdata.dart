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
  DeviceInfo(
      {this.deviceName,
      this.isDesiredConditionOn,
      this.macAddress,
      this.maxHumidity,
      this.maxTemper,
      this.minHumidity,
      this.minTemper});
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
    String path = join(documentsDirectory.path, 'DeviceInfo.db');

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
            maxHumi INTEGER
          )
        ''');
    }, onUpgrade: (db, oldVersion, newVersion) {});
  }

  //Create
  createData(DeviceInfo device) async {
    final db = await database;
    var res = await db.rawInsert(
        'INSERT INTO $TableName(name, mac, conditionflag, minTemp, maxTemp, minHumi , maxHumi) VALUES(?,?,?,?,?,?,?)',
        [device.deviceName, device.macAddress, 'false', 0, 0, 0, 0]);
    return res;
  }

  //Read
  getDevice(String macAddress) async {
    final db = await database;
    var res = await db
        .rawQuery('SELECT * FROM $TableName WHERE mac = ?', [macAddress]);
    return res.isNotEmpty
        ? DeviceInfo(
            macAddress: res.first['mac'],
            deviceName: res.first['name'],
            isDesiredConditionOn: res.first['conditionflag'],
            minTemper: res.first['minTemp'],
            maxTemper: res.first['maxTemp'],
            minHumidity: res.first['minHumi'],
            maxHumidity: res.first['maxHumi'])
        : Null;
  }

  //Update-name
  updateDeviceName(String macAddress, String newName) async {
    final db = await database;
    var res = await db.rawUpdate(
        'UPDATE $TableName SET name = ? WHERE mac = ?', [newName, macAddress]);
  }

  //Update-name
  updateDeviceCondition(String macAddress, int minTemp, int maxTemp,
      int minHumi, int maxHumi, String conditionFlag) async {
    final db = await database;
    var res = await db.rawUpdate(
        'UPDATE $TableName SET minTemp = ?, maxTemp = ?, minHumi = ?, maxHumi = ?, conditionflag = ? WHERE mac = ?',
        [minTemp, maxTemp, minHumi, maxHumi, conditionFlag, macAddress]);
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
                maxHumidity: c['maxHumi']))
            .toList()
        : [];

    return list;
  }

  //Delete
  deleteDevice(String macAddress) async {
    final db = await database;
    var res = db
        .rawDelete('DELETE FROM $TableName WHERE macAddress = ?', [macAddress]);
    return res;
  }

  //Delete All
  deleteAllDevices() async {
    final db = await database;
    db.rawDelete('DELETE FROM $TableName');
  }
}
