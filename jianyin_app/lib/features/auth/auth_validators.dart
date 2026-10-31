import '../../session/session_models.dart';

final _phoneRe = RegExp(r'^1\d{10}$');

String? validatePhone(String value) {
  final phone = value.trim();
  if (phone.isEmpty) return '请输入手机号';
  if (!_phoneRe.hasMatch(phone)) return '请输入 11 位中国大陆手机号';
  return null;
}

String? validatePassword(String value, {bool isNew = false}) {
  if (value.isEmpty) return '请输入密码';
  if (isNew && value.length < 8) return '密码至少 8 位';
  return null;
}

String? validatePasswordConfirm(String password, String confirm) {
  if (confirm.isEmpty) return '请再次输入密码';
  if (password != confirm) return '两次密码不一致';
  return null;
}

String? validateOtpCode(String value) {
  final code = value.trim();
  if (code.isEmpty) return '请输入验证码';
  if (!RegExp(r'^\d{4,6}$').hasMatch(code)) return '请输入 4–6 位数字验证码';
  return null;
}

String authErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_phone':
        return '手机号格式不正确';
      case 'weak_password':
        return '密码至少 8 位';
      case 'phone_taken':
        return '该手机号已注册';
      case 'invalid_credentials':
        return '手机号或密码错误';
      case 'unauthorized':
        return '登录已失效，请重新登录';
      case 'invalid_otp':
        return '验证码不正确或已过期，请重新获取';
      case 'invalid_sex':
        return '性别参数无效';
      default:
        if (error.message.isNotEmpty) return error.message;
    }
  }
  final message = error.toString();
  if (message.contains('SocketException') ||
      message.contains('ClientException') ||
      message.contains('Failed host lookup')) {
    return '无法连接服务，请检查网络与网关地址';
  }
  return '请求失败，请稍后重试';
}
