import { L10n } from '../localization/L10n';
import { ApiEnvelope, JsonCodec } from '../../common/JsonTypes';

export class APIResponse<T> {
  success: boolean;
  data: T | undefined;
  message: string | undefined;
  /** HTTP 状态码（注意：不是服务端业务 code） */
  code: number | undefined;
  rawResponse: ApiEnvelope | undefined;
  /** 服务端业务 code，如 'APP_NOT_ALLOWED' / 'INVALID_TOKEN'（与 HTTP 状态码区分） */
  bizCode: string | undefined;

  constructor(
    success: boolean,
    data: T | undefined,
    message: string | undefined,
    code: number | undefined,
    rawResponse: ApiEnvelope | undefined,
    bizCode: string | undefined = undefined
  ) {
    this.success = success;
    this.data = data;
    this.message = message;
    this.code = code;
    this.rawResponse = rawResponse;
    this.bizCode = bizCode;
  }

  /** 是否被服务端「应用白名单」拦截（403 + code=APP_NOT_ALLOWED） */
  get isAppNotAllowed(): boolean {
    return this.bizCode === 'APP_NOT_ALLOWED';
  }

  static success<T>(data: T, message?: string, code?: number, raw?: ApiEnvelope): APIResponse<T> {
    return new APIResponse<T>(true, data, message, code, raw);
  }

  static failure<T>(message: string, code?: number, raw?: ApiEnvelope): APIResponse<T> {
    return new APIResponse<T>(false, undefined, message, code, raw);
  }

  static fromJSON<T>(
    httpCode: number,
    json: ApiEnvelope,
    dataParser?: (data: Object, code: number) => T
  ): APIResponse<T> {
    const apiSuccess = json.success === true || json.code === 0;
    let message = json.message;
    const rawCode = APIResponse.stringValue(json.code);

    if (rawCode === 'service.NASCAB_SESSION_EXPIRED') {
      message = L10n.serviceSessionExpired;
    }

    if (rawCode === 'APP_NOT_ALLOWED') {
      // 服务端已按 Accept-Language 本地化 message；此处仅兜底 i18n key / 空文案，
      // 避免把 'auth.APP_NOT_ALLOWED' 这类 key 直接显示给用户
      if (APIResponse.looksLikeI18nKey(message)) {
        message = L10n.appNotAllowed;
      }
    }

    let data: T | undefined = undefined;
    if (apiSuccess && dataParser && json.data !== undefined) {
      data = dataParser(json.data, httpCode);
    } else if (json.data !== undefined) {
      data = json.data as T;
    }

    return new APIResponse<T>(apiSuccess, data, message, httpCode, json, rawCode);
  }

  /** 判断 message 是否是「未翻译的 i18n key」（空串视为是，交由调用方用本地文案兜底） */
  private static looksLikeI18nKey(message: string | undefined): boolean {
    if (!message || message.length === 0) {
      return true;
    }
    return message === 'APP_NOT_ALLOWED' || message.startsWith('auth.');
  }

  private static stringValue(v: number | string | undefined): string | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'string') {
      return v;
    }
    return `${v}`;
  }
}
