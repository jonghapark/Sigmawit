import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final DateTime _from = DateTime(2021, 01, 01);
  // final DateTime _to = DateTime(2021, 01, 31);
  final DateTime _to = DateTime(2021, 02, 28);

  final int _dateInterval = 7;
  final DateFormat _dateFormatLong = DateFormat('dd.MM');
  final DateFormat _dateFormatShort = DateFormat('dd');

  List<ChartSeries> _chartSeries;
  Map<String, DateTime> _dateMap;
  List<DateTime> _dateList;

  @override
  void initState() {
    super.initState();
    _getDates();
    _generateSeries();
  }

  void _getDates() {
    final dateMap = <String, DateTime>{};
    var tempDate = _from;
    while (tempDate.isBefore(_to) || tempDate == _to) {
      dateMap[_dateFormatLong.format(tempDate)] = tempDate;
      tempDate = tempDate.add(const Duration(days: 1));
    }
    _dateMap = dateMap;
    _dateList = dateMap.values.toList();
  }

  void _generateSeries() {
    _chartSeries = [];
    _chartSeries.add(
      SplineSeries<DateTime, DateTime>(
        dataSource: _dateList,
        splineType: SplineType.monotonic,
        xValueMapper: (DateTime date, _) => date,
        yValueMapper: (DateTime date, _) => 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chart Test')),
      body: Container(
        padding: EdgeInsets.fromLTRB(20, 36, 20, 36),
        child: SfCartesianChart(
          series: _chartSeries,
          primaryXAxis: DateTimeAxis(
            minimum: _from,
            maximum: _to,
            interval: _dateInterval.toDouble(),
            intervalType: DateTimeIntervalType.days,
            dateFormat: _dateFormatLong,
            labelStyle: TextStyle(fontSize: 10),
          ),
          primaryYAxis: NumericAxis(
            isVisible: false,
          ),
          // onAxisLabelRender: (AxisLabelRenderArgs args) {
          //   if (args.axisName == 'primaryXAxis') {
          //     final date = _dateMap[args.text];
          //     final index = _dateList.indexOf(date);
          //     if (index % _dateInterval == 0) {
          //       args.text = _dateFormatShort.format(date);
          //     } else {
          //       args.text = '';
          //     }
          //   }
          // },
        ),
      ),
    );
  }
}
