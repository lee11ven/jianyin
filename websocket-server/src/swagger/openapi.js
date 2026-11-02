/**
 * OpenAPI 3.0 文档（REST）。WebSocket 帧契约见仓库 docs/api/protocol.md，
 * 本文件在 info.description 中给出握手与事件摘要。
 */

const ErrorBody = {
  type: 'object',
  required: ['code', 'message'],
  properties: {
    code: { type: 'string', example: 'bad_request' },
    message: { type: 'string', example: 'phone is required' },
    sessionId: { type: 'string', description: '部分错误附带（如 session_replaced）' },
  },
};

const PublicUser = {
  type: 'object',
  required: ['userId', 'username', 'phone', 'sex', 'plan'],
  properties: {
    userId: { type: 'string', example: 'u-abcdef0123456789' },
    username: { type: 'string', example: '用户8000' },
    phone: { type: 'string', example: '13800138000' },
    sex: { type: 'string', enum: ['male', 'female', 'unknown'], example: 'unknown' },
    plan: { type: 'string', example: 'free', description: 'free 或套餐 id' },
    planExpiresAt: {
      type: 'integer',
      nullable: true,
      format: 'int64',
      example: null,
      description: '毫秒时间戳；free 时可为 null',
    },
  },
};

const TokenResponse = {
  type: 'object',
  required: ['token', 'role', 'deviceId', 'protocolVersion', 'expiresInSec', 'user'],
  properties: {
    token: { type: 'string', description: 'JWT（HS256）' },
    role: { type: 'string', enum: ['app', 'edge', 'wearable'], example: 'app' },
    deviceId: { type: 'string', example: 'app-demo' },
    protocolVersion: { type: 'integer', example: 1 },
    expiresInSec: { type: 'integer', example: 86400 },
    user: {
      type: 'object',
      required: ['userId', 'username', 'phone', 'sex', 'plan'],
      properties: {
        userId: { type: 'string' },
        username: { type: 'string' },
        phone: { type: 'string' },
        sex: { type: 'string', enum: ['male', 'female', 'unknown'] },
        plan: { type: 'string' },
      },
    },
  },
};

const Membership = {
  type: 'object',
  required: ['planId', 'title', 'expiresAt'],
  properties: {
    planId: { type: 'string', example: 'free' },
    title: { type: 'string', example: '免费版' },
    expiresAt: { type: 'integer', nullable: true, format: 'int64', example: null },
  },
};

const Plan = {
  type: 'object',
  required: ['id', 'title', 'price', 'unit', 'features', 'featured'],
  properties: {
    id: { type: 'string', example: 'pro_month' },
    title: { type: 'string', example: '专业月卡' },
    price: { type: 'string', example: '¥28' },
    unit: { type: 'string', example: '/ 月' },
    features: { type: 'array', items: { type: 'string' } },
    featured: { type: 'boolean' },
  },
};

const SessionPublic = {
  type: 'object',
  required: [
    'sessionId',
    'status',
    'edgeDeviceId',
    'usePhoneLandmarks',
    'createdAt',
    'lastActivityAt',
    'connections',
  ],
  properties: {
    sessionId: { type: 'string', example: 'sess-abcdef0123456789' },
    status: { type: 'string', enum: ['active', 'stopped'] },
    edgeDeviceId: { type: 'string', nullable: true },
    usePhoneLandmarks: { type: 'boolean' },
    createdAt: { type: 'integer', format: 'int64' },
    lastActivityAt: { type: 'integer', format: 'int64' },
    connections: {
      type: 'object',
      properties: {
        app: { type: 'boolean' },
        edge: { type: 'boolean' },
        wearable: { type: 'boolean' },
      },
    },
  },
};

const bearer = [{ BearerAuth: [] }];

/** @type {Record<string, unknown>} */
export const openApiDocument = {
  openapi: '3.0.3',
  info: {
    title: '见音 WebSocket 网关 API',
    version: '1.0.0',
    description: `
REST + WebSocket 网关（protocolVersion: 1）。字段契约以仓库 \`docs/api/protocol.md\` 为准。

## 鉴权

除 \`/health\` 与 \`/api/v1/auth/*\` 外，请求须携带：

\`\`\`
Authorization: Bearer <jwt>
\`\`\`

## WebSocket（摘要）

| 路径 | 角色 |
|------|------|
| \`/ws/app\` | App（一期必需） |
| \`/ws/edge\` | 边缘 |
| \`/ws/wearable\` | 穿戴 |

握手：Header \`Authorization: Bearer <jwt>\`；Query \`deviceId\`、\`protocolVersion=1\`；App 另带 REST 返回的 \`sessionId\`。**禁止**在 Query 传 token。

常用文本事件：\`ping\`/\`pong\`、\`landmarks\`（上行）、\`recognition\`/\`speech\`/\`audio.header\`（下行）、\`error\`。

\`POST /api/v1/sessions\` 返回的 \`wsUrl\` 按请求 Host 生成，客户端可直接连接。
`.trim(),
  },
  servers: [
    { url: 'http://127.0.0.1:8000', description: '本机默认' },
    { url: 'http://{host}:{port}', description: '局域网 / 自定义', variables: {
      host: { default: '192.168.1.100' },
      port: { default: '8000' },
    } },
  ],
  tags: [
    { name: 'Health', description: '健康检查' },
    { name: 'Auth', description: 'OTP / 注册 / 登录 / 演示 Token' },
    { name: 'User', description: '当前用户' },
    { name: 'History', description: '字幕历史' },
    { name: 'Membership', description: '会员套餐' },
    { name: 'Devices', description: '设备列表' },
    { name: 'Gestures', description: '词表' },
    { name: 'Sessions', description: '识别会话' },
  ],
  components: {
    securitySchemes: {
      BearerAuth: {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        description: 'HS256 JWT；payload 含 userId / role / deviceId 等',
      },
    },
    schemas: {
      Error: ErrorBody,
      PublicUser,
      TokenResponse,
      Membership,
      Plan,
      SessionPublic,
      HealthResponse: {
        type: 'object',
        required: ['status', 'protocolVersion'],
        properties: {
          status: { type: 'string', example: 'ok' },
          protocolVersion: { type: 'integer', example: 1 },
        },
      },
      SendOtpRequest: {
        type: 'object',
        required: ['phone'],
        properties: {
          phone: { type: 'string', pattern: '^1\\d{10}$', example: '13800138000' },
        },
      },
      SendOtpResponse: {
        type: 'object',
        required: ['sent', 'phone'],
        properties: {
          sent: { type: 'boolean', example: true },
          phone: { type: 'string' },
          code: {
            type: 'string',
            description: '仅非 production（debug）返回，便于联调',
            example: '123456',
          },
        },
      },
      VerifyOtpRequest: {
        type: 'object',
        required: ['phone', 'code'],
        properties: {
          phone: { type: 'string', example: '13800138000' },
          code: { type: 'string', example: '123456' },
        },
      },
      VerifyOtpResponse: {
        type: 'object',
        required: ['valid', 'phone'],
        properties: {
          valid: { type: 'boolean', example: true },
          phone: { type: 'string' },
        },
      },
      RegisterRequest: {
        type: 'object',
        required: ['phone', 'password', 'code'],
        properties: {
          phone: { type: 'string', example: '13800138000' },
          password: { type: 'string', minLength: 8, example: 'password1' },
          code: { type: 'string', description: 'send-otp 下发的 6 位码', example: '123456' },
          deviceId: { type: 'string', description: '可选本机设备 ID' },
        },
      },
      LoginRequest: {
        type: 'object',
        required: ['phone', 'password'],
        properties: {
          phone: { type: 'string', example: '13800138000' },
          password: { type: 'string', example: 'password1' },
          deviceId: { type: 'string' },
        },
      },
      DemoTokenRequest: {
        type: 'object',
        properties: {
          role: { type: 'string', enum: ['app', 'edge', 'wearable'], default: 'app' },
          deviceId: { type: 'string' },
        },
      },
      PatchMeRequest: {
        type: 'object',
        properties: {
          username: { type: 'string', maxLength: 32, example: '林晓' },
          sex: { type: 'string', enum: ['male', 'female', 'unknown'] },
        },
      },
      HistoryDaysResponse: {
        type: 'object',
        required: ['days'],
        properties: {
          days: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                iso: { type: 'string', example: '2026-11-02' },
                label: { type: 'string', example: '今天' },
                items: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      id: { type: 'string' },
                      time: { type: 'string', example: '10:24' },
                      text: { type: 'string' },
                      ts: { type: 'integer', format: 'int64' },
                    },
                  },
                },
              },
            },
          },
        },
      },
      SubscribeRequest: {
        type: 'object',
        required: ['planId'],
        properties: {
          planId: {
            type: 'string',
            enum: ['pro_month', 'pro_year'],
            description: '不可订阅 free',
            example: 'pro_month',
          },
        },
      },
      DevicesResponse: {
        type: 'object',
        required: ['devices'],
        properties: {
          devices: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                deviceId: { type: 'string' },
                role: { type: 'string', enum: ['app', 'edge', 'wearable'] },
                online: { type: 'boolean' },
                lastSeen: { type: 'integer', format: 'int64' },
                accountKey: { type: 'string', nullable: true },
              },
            },
          },
        },
      },
      GesturesCatalog: {
        type: 'object',
        required: ['vocabVersion', 'language', 'gestures'],
        properties: {
          vocabVersion: { type: 'string', example: '2026.04.1' },
          language: { type: 'string', example: 'CSL' },
          gestures: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'string', example: 'hello' },
                text: { type: 'string', example: '你好' },
                aliases: { type: 'array', items: { type: 'string' } },
              },
            },
          },
        },
      },
      CreateSessionRequest: {
        type: 'object',
        properties: {
          edgeDeviceId: {
            type: 'string',
            description: '边缘设备 ID；普通 App 会话可省略',
            example: 'edge-001',
          },
          usePhoneLandmarks: { type: 'boolean', default: true },
        },
      },
      CreateSessionResponse: {
        type: 'object',
        required: ['sessionId', 'protocolVersion', 'wsUrl'],
        properties: {
          sessionId: { type: 'string', example: 'sess-abcdef0123456789' },
          protocolVersion: { type: 'integer', example: 1 },
          wsUrl: {
            type: 'string',
            example: 'ws://127.0.0.1:8000/ws/app',
            description: '按请求 Host / X-Forwarded-Proto 生成',
          },
        },
      },
      StopSessionResponse: {
        type: 'object',
        required: ['sessionId', 'status'],
        properties: {
          sessionId: { type: 'string' },
          status: { type: 'string', enum: ['stopped'], example: 'stopped' },
        },
      },
      SessionHistoryResponse: {
        type: 'object',
        required: ['sessionId', 'history'],
        properties: {
          sessionId: { type: 'string' },
          history: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                utteranceId: { type: 'string' },
                text: { type: 'string' },
                confidence: { type: 'number' },
                glossIds: { type: 'array', items: { type: 'string' } },
                ts: { type: 'integer', format: 'int64' },
              },
            },
          },
        },
      },
    },
    responses: {
      Unauthorized: {
        description: '无效或过期 Token',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/Error' },
            example: { code: 'unauthorized', message: 'invalid or expired token' },
          },
        },
      },
      BadRequest: {
        description: '请求参数错误',
        content: {
          'application/json': { schema: { $ref: '#/components/schemas/Error' } },
        },
      },
      NotFound: {
        description: '资源不存在',
        content: {
          'application/json': { schema: { $ref: '#/components/schemas/Error' } },
        },
      },
      Forbidden: {
        description: '无权访问他人会话',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/Error' },
            example: { code: 'unauthorized', message: 'session belongs to another account' },
          },
        },
      },
    },
  },
  paths: {
    '/health': {
      get: {
        tags: ['Health'],
        summary: '健康检查',
        operationId: 'getHealth',
        responses: {
          200: {
            description: '服务正常',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/HealthResponse' } },
            },
          },
        },
      },
    },
    '/api/v1/auth/send-otp': {
      post: {
        tags: ['Auth'],
        summary: '发送注册短信验证码',
        description:
          '验证码仅存内存、不落盘，有效期 60s；同号再次请求会覆盖旧码。非 production 响应含 `code`。',
        operationId: 'sendOtp',
        requestBody: {
          required: true,
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/SendOtpRequest' } },
          },
        },
        responses: {
          200: {
            description: '已受理（演示环境未必真发短信）',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/SendOtpResponse' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
        },
      },
    },
    '/api/v1/auth/verify-otp': {
      post: {
        tags: ['Auth'],
        summary: '校验验证码',
        description: '注册接口内部也会校验；可单独调用做预检。',
        operationId: 'verifyOtp',
        requestBody: {
          required: true,
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/VerifyOtpRequest' } },
          },
        },
        responses: {
          200: {
            description: '验证码有效',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/VerifyOtpResponse' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
        },
      },
    },
    '/api/v1/auth/register': {
      post: {
        tags: ['Auth'],
        summary: '手机号注册',
        description:
          '必须携带有效 OTP。username 由服务端派生为「用户」+ 手机后四位，sex 固定 unknown；修改走 PATCH /me。',
        operationId: 'register',
        requestBody: {
          required: true,
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/RegisterRequest' } },
          },
        },
        responses: {
          201: {
            description: '注册成功并签发 JWT',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/TokenResponse' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
          409: {
            description: '手机号已注册',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/Error' },
                example: { code: 'phone_taken', message: 'phone already registered' },
              },
            },
          },
        },
      },
    },
    '/api/v1/auth/login': {
      post: {
        tags: ['Auth'],
        summary: '手机号登录',
        operationId: 'login',
        requestBody: {
          required: true,
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/LoginRequest' } },
          },
        },
        responses: {
          200: {
            description: '登录成功',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/TokenResponse' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
          401: {
            description: '账号或密码错误',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/Error' },
                example: { code: 'invalid_credentials', message: 'invalid phone or password' },
              },
            },
          },
        },
      },
    },
    '/api/v1/auth/demo-token': {
      post: {
        tags: ['Auth'],
        summary: '演示 JWT（仅 debug）',
        description: '仅 `NODE_ENV !== "production"` 可用；正式服返回 404。',
        operationId: 'demoToken',
        requestBody: {
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/DemoTokenRequest' } },
          },
        },
        responses: {
          200: {
            description: '签发演示 Token',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/TokenResponse' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
          404: {
            description: 'production 已禁用',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/Error' },
                example: { code: 'not_found', message: 'demo-token is disabled' },
              },
            },
          },
        },
      },
    },
    '/api/v1/me': {
      get: {
        tags: ['User'],
        summary: '当前用户资料',
        operationId: 'getMe',
        security: bearer,
        responses: {
          200: {
            description: '用户公开资料',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/PublicUser' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
      patch: {
        tags: ['User'],
        summary: '更新用户资料',
        description: '字段均可选；只更新提供的键。',
        operationId: 'patchMe',
        security: bearer,
        requestBody: {
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/PatchMeRequest' } },
          },
        },
        responses: {
          200: {
            description: '更新后的资料',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/PublicUser' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
          401: { $ref: '#/components/responses/Unauthorized' },
          404: { $ref: '#/components/responses/NotFound' },
        },
      },
    },
    '/api/v1/history': {
      get: {
        tags: ['History'],
        summary: '用户字幕历史（按日）',
        operationId: 'listHistory',
        security: bearer,
        parameters: [
          {
            name: 'from',
            in: 'query',
            schema: { type: 'string', format: 'date', example: '2026-10-01' },
            description: '起始日 YYYY-MM-DD（含）',
          },
          {
            name: 'to',
            in: 'query',
            schema: { type: 'string', format: 'date', example: '2026-11-02' },
            description: '结束日 YYYY-MM-DD（含）',
          },
        ],
        responses: {
          200: {
            description: '按日分组的历史',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/HistoryDaysResponse' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/membership/plans': {
      get: {
        tags: ['Membership'],
        summary: '会员套餐列表',
        operationId: 'listPlans',
        security: bearer,
        responses: {
          200: {
            description: '套餐列表',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['plans'],
                  properties: {
                    plans: {
                      type: 'array',
                      items: { $ref: '#/components/schemas/Plan' },
                    },
                  },
                },
              },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/membership': {
      get: {
        tags: ['Membership'],
        summary: '当前会员状态',
        operationId: 'getMembership',
        security: bearer,
        responses: {
          200: {
            description: '会员信息',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/Membership' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/membership/subscribe': {
      post: {
        tags: ['Membership'],
        summary: '开通套餐',
        description: '无支付网关；直接写入会员状态。不可订阅 free。',
        operationId: 'subscribe',
        security: bearer,
        requestBody: {
          required: true,
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/SubscribeRequest' } },
          },
        },
        responses: {
          200: {
            description: '开通后的会员状态',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/Membership' } },
            },
          },
          400: { $ref: '#/components/responses/BadRequest' },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/devices': {
      get: {
        tags: ['Devices'],
        summary: '当前账号设备列表',
        description: '仅返回 JWT userId 所属设备，不含全局视图。',
        operationId: 'listDevices',
        security: bearer,
        responses: {
          200: {
            description: '设备列表',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/DevicesResponse' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/gestures': {
      get: {
        tags: ['Gestures'],
        summary: '手语词表',
        operationId: 'listGestures',
        security: bearer,
        responses: {
          200: {
            description: '词表目录',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/GesturesCatalog' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
        },
      },
    },
    '/api/v1/sessions': {
      post: {
        tags: ['Sessions'],
        summary: '创建识别会话',
        description:
          '同一 userId 只保留最新 App 会话；旧连接会收到 WS `session_replaced`。边缘设备忙时返回 409 `device_busy`。',
        operationId: 'createSession',
        security: bearer,
        requestBody: {
          content: {
            'application/json': { schema: { $ref: '#/components/schemas/CreateSessionRequest' } },
          },
        },
        responses: {
          201: {
            description: '会话已创建',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/CreateSessionResponse' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
          409: {
            description: '边缘设备忙',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/Error' },
                example: { code: 'device_busy', message: 'edge device is busy' },
              },
            },
          },
        },
      },
    },
    '/api/v1/sessions/{id}': {
      get: {
        tags: ['Sessions'],
        summary: '查询会话状态',
        operationId: 'getSession',
        security: bearer,
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
            description: 'sessionId',
          },
        ],
        responses: {
          200: {
            description: '会话公开状态',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/SessionPublic' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
          403: { $ref: '#/components/responses/Forbidden' },
          404: {
            description: '会话不存在',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/Error' },
                example: { code: 'session_not_found', message: 'session not found' },
              },
            },
          },
        },
      },
    },
    '/api/v1/sessions/{id}/stop': {
      post: {
        tags: ['Sessions'],
        summary: '结束会话',
        operationId: 'stopSession',
        security: bearer,
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
          },
        ],
        responses: {
          200: {
            description: '已停止',
            content: {
              'application/json': { schema: { $ref: '#/components/schemas/StopSessionResponse' } },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
          403: { $ref: '#/components/responses/Forbidden' },
          404: { $ref: '#/components/responses/NotFound' },
        },
      },
    },
    '/api/v1/sessions/{id}/history': {
      get: {
        tags: ['Sessions'],
        summary: '会话内识别历史',
        description: '内存会话历史（进程内）；用户持久化历史见 GET /api/v1/history。',
        operationId: 'getSessionHistory',
        security: bearer,
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
          },
        ],
        responses: {
          200: {
            description: '会话文本历史',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/SessionHistoryResponse' },
              },
            },
          },
          401: { $ref: '#/components/responses/Unauthorized' },
          403: { $ref: '#/components/responses/Forbidden' },
          404: { $ref: '#/components/responses/NotFound' },
        },
      },
    },
  },
};
