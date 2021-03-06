import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

// 사용자가 주어진 카메라를 사용하여 사진을 찍을 수 있는 화면
class TakePictureScreen extends StatefulWidget {
  final CameraDescription camera;

  const TakePictureScreen({
    Key key,
    @required this.camera,
  }) : super(key: key);

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  CameraController _controller;
  Future<void> _initializeControllerFuture;
  var defaultAspect = 0.8;

  @override
  void initState() {
    super.initState();
    // 카메라의 현재 출력물을 보여주기 위해 CameraController를 생성합니다.
    _controller = CameraController(
      // 이용 가능한 카메라 목록에서 특정 카메라를 가져옵니다.
      widget.camera,
      // 적용할 해상도를 지정합니다.
      ResolutionPreset.ultraHigh,
    );

    // 다음으로 controller를 초기화합니다. 초기화 메서드는 Future를 반환합니다.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // 위젯의 생명주기 종료시 컨트롤러 역시 해제시켜줍니다.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      // 카메라 프리뷰를 보여주기 전에 컨트롤러 초기화를 기다려야 합니다. 컨트롤러 초기화가
      // 완료될 때까지 FutureBuilder를 사용하여 로딩 스피너를 보여주세요.
      body: Container(
          padding: EdgeInsets.only(bottom: 5),
          child: FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return Transform.scale(
                  scale: 1.0,
                  child: AspectRatio(
                    aspectRatio: defaultAspect,
                    child: OverflowBox(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: size.aspectRatio >= defaultAspect
                            ? BoxFit.fitHeight
                            : BoxFit.fitWidth,
                        child: Container(
                          width: size.aspectRatio >= defaultAspect
                              ? size.height
                              : size.width,
                          height: size.aspectRatio >= defaultAspect
                              ? size.height / _controller.value.aspectRatio
                              : size.width / _controller.value.aspectRatio,
                          child: Stack(
                            children: <Widget>[
                              CameraPreview(_controller),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // CameraPreview(_controller);
              } else {
                // 그렇지 않다면, 진행 표시기를 보여줍니다.
                return Center(child: CircularProgressIndicator());
              }
            },
          )),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Color.fromRGBO(63, 63, 63, 1),
        child: Icon(Icons.camera_alt),
        // onPressed 콜백을 제공합니다.
        onPressed: () async {
          // try / catch 블럭에서 사진을 촬영합니다. 만약 뭔가 잘못된다면 에러에
          // 대응할 수 있습니다.
          try {
            // 카메라 초기화가 완료됐는지 확인합니다.
            await _initializeControllerFuture;
            DateTime now = DateTime.now();

            // path 패키지를 사용하여 이미지가 저장될 경로를 지정합니다.
            final path = join(
              // 본 예제에서는 임시 디렉토리에 이미지를 저장합니다. `path_provider`
              // 플러그인을 사용하여 임시 디렉토리를 찾으세요.
              (await getTemporaryDirectory()).path,
              now.year.toString() +
                  now.month.toString() +
                  now.day.toString() +
                  now.hour.toString() +
                  now.minute.toString() +
                  now.second.toString() +
                  '.jpg',
            );

            // 사진 촬영을 시도하고 저장되는 경로를 로그로 남깁니다.
            await _controller.takePicture(path);
            //print('save Direct: ' + path2);

            // 사진을 촬영하면, 새로운 화면으로 넘어갑니다.
            Navigator.pop(context, path);
          } catch (e) {
            // 만약 에러가 발생하면, 콘솔에 에러 로그를 남깁니다.
            print(e);
          }
        },
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.miniCenterFloat,
    );
  }
}
