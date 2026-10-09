const { body, query, param, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function isAnyOrStringArray(value) {
  if (value === undefined || value === null) return true;
  if (value === 'ANY') return true;
  if (Array.isArray(value)) {
    return value.every(v => typeof v === 'string' && String(v).trim());
  }
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) return false;
    if (text === 'ANY') return true;
    try {
      const parsed = JSON.parse(text);
      return Array.isArray(parsed) && parsed.every(v => typeof v === 'string' && String(v).trim());
    } catch (_) {
      return true;
    }
  }
  return false;
}

const UserValidation = {
  validateListBody() {
    return [
      body('page').optional().isInt({ min: 1 }).withMessage('validation.PAGE_NUMBER_INVALID'),
      body('limit').optional().isInt({ min: 1, max: 100 }).withMessage('validation.LIMIT_INVALID'),
      body('keyword').optional().isLength({ min: 0, max: 100 }).withMessage('validation.KEYWORD_LENGTH_INVALID'),
    ];
  },

  validateCreateUser() {
    return [
      body('username').isString().isLength({ min: 3, max: 20 }).withMessage('validation.USERNAME_LENGTH_INVALID'),
      // 子账号密码不做复杂度校验：密码强度要求只对超级管理员账号生效。
      // 管理员可以给不同子账号设置相同或简单密码，这里仅保证密码非空。
      body('password')
        .isString()
        .withMessage('validation.PASSWORD_REQUIRED')
        .notEmpty()
        .withMessage('validation.PASSWORD_REQUIRED'),
      body('user_remark').optional({ nullable: true }).isString().isLength({ max: 500 }).withMessage('validation.VALIDATION_ERROR'),
      body('phone').optional({ nullable: true }).isString().isLength({ max: 32 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateUpdateUser() {
    return [
      param('id').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('username').optional().isString().isLength({ min: 3, max: 20 }).withMessage('validation.USERNAME_LENGTH_INVALID'),
      // 同创建：子账号改密不做复杂度校验，留空表示不修改密码
      body('password')
        .optional()
        .isString()
        .withMessage('validation.PASSWORD_REQUIRED'),
      body('user_remark').optional({ nullable: true }).isString().isLength({ max: 500 }).withMessage('validation.VALIDATION_ERROR'),
      body('phone').optional({ nullable: true }).isString().isLength({ max: 32 }).withMessage('validation.VALIDATION_ERROR'),
      body('is_active').optional().isBoolean().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateBatchDelete() {
    return [body('ids').isArray({ min: 1 }).withMessage('validation.VALIDATION_ERROR')];
  },

  validateSetPermissions() {
    return [
      param('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('permissions').isArray().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_path').isString().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.action').isIn(['view', 'download', 'update', 'delete', 'upload', 'share']).withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_type').optional().isIn(['file']).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGetPermissions() {
    return [body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateSetAccessPolicy() {
    return [
      param('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('allowed_apps').optional({ nullable: true }).isArray().withMessage('validation.VALIDATION_ERROR'),
      body('allowed_apps.*').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('permissions').optional().isArray().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_path').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.action')
        .optional()
        .isIn(['view', 'download', 'update', 'delete', 'upload', 'share'])
        .withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_type').optional().isIn(['file']).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGetUserFileLogs() {
    return [
      body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('page').optional().isInt({ min: 1 }).withMessage('validation.PAGE_NUMBER_INVALID'),
      body('pageSize').optional().isInt({ min: 1, max: 200 }).withMessage('validation.LIMIT_INVALID'),
      body('types').optional({ nullable: true }).isArray().withMessage('validation.VALIDATION_ERROR'),
      body('types.*').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('stateList').optional({ nullable: true }).isArray().withMessage('validation.VALIDATION_ERROR'),
      body('stateList.*').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('keyword').optional().isLength({ min: 0, max: 100 }).withMessage('validation.KEYWORD_LENGTH_INVALID'),
    ];
  },

  validateTwofaUid() {
    return [body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateTwofaUidCode() {
    return [
      body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('code').notEmpty().withMessage('validation.VALIDATION_ERROR').isString().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateCreateScopedToken() {
    return [
      body('allow_api').optional().custom(isAnyOrStringArray).withMessage('validation.VALIDATION_ERROR'),
      body('allow_path').optional().custom(isAnyOrStringArray).withMessage('validation.VALIDATION_ERROR'),
      body('expiresIn')
        .optional()
        .isString()
        .matches(/^\d+[smhd]$/)
        .withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  handleValidationErrors(req, res, next) {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      const errorMessages = errors
        .array()
        .map(error => getLocalizedMessage(req, error.msg))
        .join(', ');

      return res.status(400).json({
        success: false,
        message: errorMessages,
      });
    }
    next();
  },
};

module.exports = UserValidation;
