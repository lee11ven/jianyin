# session/

REST 建停会话、JWT 鉴权与 Home 生命周期（P1-1）。

| 文件 | 职责 |
|------|------|
| `api_client.dart` | health / register / login / me / history / membership / sessions |
| `auth_store.dart` | JWT + user 持久化；登录注册写 Token |
| `device_id_store.dart` | 本机随机 `deviceId` |
| `home_session_controller.dart` | 进 Home 建会话 → WS；离 Home 关 WS + REST stop |
| `session_models.dart` | Token / User / History / Membership 模型 |

除 login/register/health 外，REST 均带 `Authorization: Bearer <jwt>`。
