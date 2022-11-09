import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:faint_down/Common/Constant.dart';
import 'package:faint_down/Utility/FileUtil.dart';
import 'package:faint_down/Utility/HttpUtil.dart' as http;
import 'package:faint_down/Utility/SharedPreferencesUtil.dart';

enum LoginType {
  guilinJW,
  guilinOA,
  nanning,
  fitness,
  attendance
} //华科教务 华科统一身份认证 校区 体测 考勤 不同对象的登录

class LoginInfo with ChangeNotifier {
  LoginInfo() {
    init();
  }

  SharedPreferenceUtil su;

  //账号输入控制器，密码输入控制器，验证码输入控制器
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _verifyCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true; //密码的明文控制
  bool _savePwd = true; //记住密码开关控制

  LoginType _loginType = LoginType.guilinJW; //登陆教务

  Uint8List _verifyCodeImage; //验证码图片
  final Map<String, String> _cookie = Map();
  String _msg = '';

  TextEditingController get studentIdController => _studentIdController;
  TextEditingController get passwordController => _passwordController;
  TextEditingController get verifyCodeController => _verifyCodeController;

  bool get isLoading => _isLoading;
  bool get obscure => _obscure;
  bool get savePwd => _savePwd;
  String get msg => _msg;
  Uint8List get verifyCodeImage => _verifyCodeImage;

  LoginType get loginType => _loginType;

  set obscure(bool obscure) {
    _obscure = !_obscure;
    notifyListeners();
  }

  set savePwd(bool savePwd) {
    _savePwd = savePwd;
    notifyListeners();
  }

  /// 更换登录方式
  Future<void> changeLoginType(int loginTypeIndex) async {
    _loginType = LoginType.values[loginTypeIndex];
    if (loginTypeIndex < 2) {
      Constant.URL_JW = Constant.URL_JW_GLUT;
    } else {
      Constant.URL_JW = Constant.URL_JW_GLUT_NN;
    }
    su.setInt('login_type', loginTypeIndex);

    setControllerPassword();
    notifyListeners();
  }

  /// 登录操作
  Future<bool> login() async {
    String studentId = _studentIdController.text.trim();
    String password = _passwordController.text.trim();
    String verifyCode = _verifyCodeController.text.trim();

    _isLoading = true;
    notifyListeners();

    Map<String, dynamic> result;
    if (_loginType == LoginType.guilinOA) {
      result =
          await _loginOA(studentId, password, verifyCode, mapCookieToString());
    } else {
      result =
          await _loginJW(studentId, password, verifyCode, mapCookieToString());
    }

    if (result['success']) {
      FileUtil fp = await FileUtil.getInstance();
      // 写 session 到文件 TODO 以json存储
      fp.writeFile(
          result['cookie'], Constant.LIST_LOGIN_TITLE[loginType.index][3]);

      _msg = '登录成功, 该界面无需理会, 可跳转至别的界面';
    } else {
      _msg = '登录失败, 检查下登录信息是否有误';
    }

    savePassword(); // 不管登录成不成功，写了再说

    _isLoading = false;
    notifyListeners();
    return result['success'];
  }

  /// 切换的登录方式的时候切换密码
  Future<void> setControllerPassword() async {
    String pwd =
        await su.getString(Constant.LIST_LOGIN_TITLE[_loginType.index][1]);
    _passwordController.text = pwd;
  }

  /// 登录的时候写进 sharedpreference
  Future<void> savePassword() async {
    String password = _passwordController.text;
    String studentId = _studentIdController.text;
    if (!_savePwd) {
      password = '';
      studentId = '';
      su.setBool('remember_pwd', false);
    }
    su.setString(Constant.LIST_LOGIN_TITLE[loginType.index][1], password);
    su.setString('student_id', studentId);
  }

  /// 刷新验证码
  Future<void> refreshVerifyCodeImage() async {
    Map<String, dynamic> result = await _getCode();
    if (result['success']) {
      _verifyCodeImage = result['data']['image'];
      _msg = '刷新成功';
    } else {
      _msg = '网络有点问题，获取验证码失败啦';
    }
    notifyListeners();
  }

  Future<void> init() async {
    su = await SharedPreferenceUtil.getInstance();
    _loginType = LoginType.values[
        await su.getInt('login_type')]; // 由于拥有了屏风校区的选项,原来的campus改成了登录选项,于1.4.4改
    _studentIdController.text = await su.getString('student_id');
    changeLoginType(_loginType.index);
    await refreshVerifyCodeImage();
  }

  // HTTP 请求登录部分
  /// 获取验证码
  Future<Map<String, dynamic>> _getCode() async {
    //http://jw.glut.edu.cn/academic/getCaptcha.do
    //String verifyCodeURL = Constant.LIST_LOGIN_TITLE[_loginType.index][2];
    String verifyCodeURL = "https://pass.hust.edu.cn/cas/code";
    // if (kDebugMode) {
    //   print("158  $verifyCodeURL");
    // }
    try {
      var response = await http.get(verifyCodeURL, '');
      if (kDebugMode) {
        print(response.headers);
      }
      _parseRawCookies(response.headers['set-cookie']);
      var data = {'image': response.bodyBytes};
      return {'success': true, 'data': data};
    } catch (e) {
      return {'success': false, 'data': e};
    }
  }

  void _parseRawCookies(String rawCookie) {
    for (var item in rawCookie.split(',')) {
      List<String> cookie = item.split(';')[0].split('=');
      if (cookie[0].contains("JSESSIONID") == false) {
        continue;
      }
      _cookie[cookie[0]] = cookie[1];
      // print(cookie[0]);
      // print(cookie[1]);
    }
    _cookie["cookiesession1"] = "678B286E67898901234ABCDEFGHICBA9";
    _cookie["Language"] = "zh_CN";
    _cookie["cas_hash"] = "";
  }

  String mapCookieToString() {
    String result = '';
    _cookie.forEach((key, value) {
      result += '$key=$value; ';
    });
    return result;
  }

  //登录教务
  Future<Map<String, dynamic>> _loginJW(String studentId, String password,
      String verifyCode, String cookie) async {
    try {
      var postData = {
        "j_username": studentId,
        "j_password": password,
        "j_captcha": verifyCode.trim().toString()
      };
      var response = await http
          .post(Constant.URL_JW + Constant.URL_LOGIN, postData, cookie: cookie);
      //http://jw.glut.edu.cn/academic/j_acegi_security_check
      // if (kDebugMode) {
      //   print(Constant.URL_JW + Constant.URL_LOGIN);
      // }
      // if (kDebugMode) {
      //   print(response.headers);
      // }
      if (response.headers['location'].contains('index_new')) {
        _parseRawCookies(response.headers['set-cookie']);
        return {'success': true, 'cookie': mapCookieToString()};
      } else {
        return {'success': false, 'cookie': ''};
      }
    } catch (e) {
      return {'success': false, 'cookie': ''};
    }
  }

  Future<Map<String, dynamic>> _loginOA(String studentId, String password,
      String verifyCode, String cookie) async {
    try {
      //var responseLt = await http.get(Constant.URL_LOGIN_OA, cookie);
      var responseLt = await http.get(
          "https://pass.hust.edu.cn/cas/login?service=http%3A%2F%2Fhub.m.hust.edu.cn%2Fkcb%2Ftodate%2Fnamecourse.action",
          cookie);
      //log(jsonEncode(responseLt.body));
      RegExp ltExp = RegExp('name="lt" value="(.*)"');
      RegExpMatch ltMatch = ltExp.firstMatch(responseLt.body);
      String lt = ltMatch.group(1);
      //print("lt:$lt");

      // RegExp rsaExp2 = RegExp('name="rsa" value="(.*)"');
      // RegExpMatch rsaMatch2 = rsaExp2.firstMatch(responseLt.body);
      // String rsa2 = rsaMatch2.group(1);

      // RegExp ulExp2 = RegExp('name="ul" value="(.*)"');
      // RegExpMatch ulMatch2 = ulExp2.firstMatch(responseLt.body);
      // String ul2 = ulMatch2.group(1);

      // RegExp plExp2 = RegExp('name="pl" value="(.*)"');
      // RegExpMatch plMatch2 = plExp2.firstMatch(responseLt.body);
      // String pl2 = plMatch2.group(1);

      RegExp executionExp2 = RegExp('name="execution" value="(.*)"');
      RegExpMatch executionMatch2 = executionExp2.firstMatch(responseLt.body);
      String execution2 = executionMatch2.group(1);

      RegExp notExitNumberExp2 = RegExp('id="not_exit_number" value="(.*)"');
      RegExpMatch notExitNumberMatch2 =
          notExitNumberExp2.firstMatch(responseLt.body);
      String notExitNumber2 = notExitNumberMatch2.group(1);

      RegExp serviceIdExp2 = RegExp('id="service_id" value="(.*)"');
      RegExpMatch serviceIdMatch2 = serviceIdExp2.firstMatch(responseLt.body);
      String serviceId2 = serviceIdMatch2.group(1);
      //print("$execution2,$notExitNumber2,$serviceId2");
      Map<String, dynamic> postData = {
        'code': verifyCode,
        // 'ul': 10,
        // 'pl': 13,
        // 'lt': lt,
        'execution': execution2,
        '_eventId': 'submit',
        // 'not_exit_number': notExitNumber2,
        // 'service_id': serviceId2,
        'pd': password,
        'un': studentId
      };
      // 这谜一样的统一身份认证要跳转3次
      // 先登录统一身份认证
      print("$verifyCode\n$password\n$studentId");
      print(cookie);
      var response = await http.post(
          "https://pass.hust.edu.cn/cas/login?service=http%3A%2F%2Fhub.m.hust.edu.cn%2Fkcb%2Ftodate%2Fnamecourse.action",
          postData,
          cookie: cookie);
      log(jsonEncode("there:${response.headers}"));
      if (response.body == '') {
        // 登录成功
        // 第一次跳转 获取乱七八糟的认证信息
        // 以下虽然可以走 get 但是写着走 post 是有原因的，可以get，但没必要
        response = await http.post(Constant.URL_OA_TO_JW, {'test': '1'},
            cookie: cookie);
        // 第二次跳转登录教务
        response = await http.post(response.headers['location'], {'test': '1'});
        // 第三次跳转带着验证码和验证码cookie登录到教务并返回cookie，一般都是登录成功
        _parseRawCookies(response.headers['set-cookie']);
        response = await http.post(response.headers['location'], {'test': '1'},
            cookie: mapCookieToString());
        if (response.headers['location'].contains('index_new')) {
          _parseRawCookies(response.headers['set-cookie']);
          return {'success': true, 'cookie': mapCookieToString()};
        } else {
          return {'success': false, 'cookie': ''};
        }
      }
    } catch (e) {
      return {'success': false, 'cookie': ''};
    }
    return {'success': false, 'cookie': ''};
  }
}
