require('dotenv').config();

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const {
  sendEventEmail,
  sendPasswordResetEmail
} = require('./email_service');

const app = express();
const PORT = Number(process.env.PORT || 3000);

app.use(cors());
app.use(express.json({ limit: '20kb' }));

// ===== MODEL USER =====
const userSchema = new mongoose.Schema(
  {
    fullName: {
      type: String,
      required: true,
      trim: true
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true
    },
   passwordHash: {
     type: String,
     required: true,
     select: false
   },

role: {
  type: String,
  enum: ['admin', 'user'],
  default: 'user'
},

// ===== KHÔI PHỤC MẬT KHẨU =====

// Lưu mã xác minh dưới dạng đã băm
resetCodeHash: {
  type: String,
  default: null,
  select: false
},

// Thời điểm mã hết hạn
resetCodeExpiresAt: {
  type: Date,
  default: null,
  select: false
},

// Số lần nhập mã không đúng
resetAttempts: {
  type: Number,
  default: 0,
  select: false
},

// Thời điểm yêu cầu mã gần nhất
resetRequestedAt: {
  type: Date,
  default: null,
  select: false
}

  },
  { timestamps: true }
);

const User = mongoose.model('User', userSchema);

// ===== MODEL TASK =====
const taskSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true
    },
    description: {
      type: String,
      default: ''
    },
    status: {
      type: String,
      enum: ['pending', 'in_progress', 'completed'],
      default: 'pending'
    },
    dueDate: { type: Date, default: null },
    startDate: { type: Date, default: null },
    priority: {
      type: String,
      enum: ['low', 'medium', 'high'],
      default: 'medium'
    },
    owner: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },

    assignedTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true
    },
    // Danh sách người được giao công việc
    assigneeIds: [{
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    }],

    // Người phụ trách chính
    primaryAssigneeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null
    }
  },
  { timestamps: true }
);

const Task = mongoose.model('Task', taskSchema);
// ===== MODEL CHIA SẺ CÔNG VIỆC =====

const taskShareSchema = new mongoose.Schema(
  {
    taskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Task',
      required: true
    },

    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    },

    permission: {
      type: String,
      enum: ['viewer', 'editor'],
      required: true
    },

    sharedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    }
  },
  { timestamps: true }
);

// Không cho chia sẻ trùng người trong cùng công việc
taskShareSchema.index(
  { taskId: 1, userId: 1 },
  { unique: true }
);

const TaskShare = mongoose.model(
  'TaskShare',
  taskShareSchema
);
// ===== THÔNG BÁO, NHẬT KÝ EMAIL VÀ LỊCH SỬ HOẠT ĐỘNG =====
const Notification = mongoose.model('Notification', new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', default: null },
  type: { type: String, required: true },
  title: { type: String, required: true },
  message: { type: String, required: true },
  isRead: { type: Boolean, default: false }
}, { timestamps: true }));

const EmailLog = mongoose.model('EmailLog', new mongoose.Schema({
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', default: null },
  recipientEmail: { type: String, required: true },
  eventType: { type: String, required: true },
  subject: { type: String, required: true },
  status: { type: String, enum: ['pending', 'sent', 'failed'], default: 'pending' },
  attempts: { type: Number, default: 0 },
  errorMessage: { type: String, default: '' },
  sentAt: { type: Date, default: null }
}, { timestamps: true }));

const TaskActivity = mongoose.model('TaskActivity', new mongoose.Schema({
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true, index: true },
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  action: { type: String, required: true },
  details: { type: mongoose.Schema.Types.Mixed, default: {} }
}, { timestamps: true }));

async function logActivity(taskId, userId, action, details = {}) {
  try { await TaskActivity.create({ taskId, userId, action, details }); }
  catch (error) { console.error('Activity log:', error.message); }
}

// Gửi email có lưu lịch sử; không làm hỏng thao tác chính nếu SMTP gặp lỗi.
async function notifyUsers({ userIds, task, type, title, message, email = true }) {
  try {
    const ids = [...new Set(userIds.map(String))].filter(mongoose.isValidObjectId);
    if (!ids.length) return;
    await Notification.insertMany(ids.map(userId => ({
      userId, taskId: task._id, type, title, message
    })));
    if (!email) return;
    const users = await User.find({ _id: { $in: ids } }).select('email fullName').lean();
    await Promise.allSettled(users.map(async user => {
      const log = await EmailLog.create({
        taskId: task._id, recipientEmail: user.email, eventType: type,
        subject: `Task Manager - ${title}`, attempts: 1
      });
      try {
        await sendEventEmail({ to: user.email, recipientName: user.fullName,
          subject: log.subject, message });
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { status: 'sent', sentAt: new Date(), errorMessage: '' }
        });
      } catch (error) {
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { status: 'failed', errorMessage: String(error.message).slice(0, 500) }
        });
        console.error('Send notification email:', error.message);
      }
    }));
  } catch (error) { console.error('Notify users:', error.message); }
}

function taskAudience(task) {
  return [...new Set([
    String(task.owner),
    ...(task.assigneeIds || []).map(String),
    ...(task.assignedTo ? [String(task.assignedTo)] : [])
  ])];
}

// ===== JWT =====
function createToken(user) {
  return jwt.sign(
    { userId: user._id.toString() },
    process.env.JWT_SECRET,
    { expiresIn: '1d', algorithm: 'HS256' }
  );
}

function authenticate(req, res, next) {
  const authorization = req.headers.authorization || '';
  const parts = authorization.split(' ');

  if (
    parts.length !== 2 ||
    parts[0] !== 'Bearer' ||
    !parts[1]
  ) {
    return res.status(401).json({
      message: 'Vui lòng đăng nhập'
    });
  }

  try {
    const payload = jwt.verify(
      parts[1],
      process.env.JWT_SECRET,
      { algorithms: ['HS256'] }
    );

    req.userId = payload.userId;
    next();
  } catch (error) {
    return res.status(401).json({
      message: 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn'
    });
  }
}

// ===== KIỂM TRA QUYỀN ADMIN =====
async function requireAdmin(req, res, next) {
  try {
    const user = await User.findById(req.userId);

    if (!user || user.role !== 'admin') {
      return res.status(403).json({
        message: 'Bạn không có quyền quản trị'
      });
    }

    next();
  } catch (error) {
    return res.status(500).json({
      message: 'Không thể kiểm tra quyền truy cập'
    });
  }
}

// ===== API KIỂM TRA QUYỀN ADMIN =====
app.get('/api/admin/check', authenticate, requireAdmin, (req, res) => {
  res.status(200).json({
    message: 'Xác thực quyền Admin thành công'
  });
});

// ===== ADMIN: XEM TẤT CẢ CÔNG VIỆC =====
app.get('/api/admin/tasks', authenticate, requireAdmin, async (req, res) => {
  try {
    const tasks = await Task.find({})
      .populate('owner', 'fullName email')
      .sort({ createdAt: -1 })
      .limit(100)
      .lean();

    return res.status(200).json({
      message: 'Lấy danh sách công việc thành công',
      tasks
    });
  } catch (error) {
    console.error('Admin list tasks error:', error.message);

    return res.status(500).json({
      message: 'Không thể tải danh sách công việc'
    });
  }
});


// ===== KIỂM TRA SERVER =====
app.get('/', (req, res) => {
  res.json({
    message: 'Task Manager API đang hoạt động!',
    database: 'MongoDB'
  });
});

 // ===== ADMIN: THÊM CÔNG VIỆC =====
app.post('/api/admin/tasks', authenticate, requireAdmin, async (req, res) => {
  try {
    let taskData;

    try {
      taskData = validateTaskInput(req.body);
    } catch (error) {
      return res.status(400).json({
        message: error.message
      });
    }

    const { ownerId } = req.body;

    if (
      typeof ownerId !== 'string' ||
      !mongoose.isValidObjectId(ownerId)
    ) {
      return res.status(400).json({
        message: 'Mã chủ sở hữu không hợp lệ'
      });
    }

    const owner = await User.findById(ownerId).select('_id');

    if (!owner) {
      return res.status(404).json({
        message: 'Không tìm thấy chủ sở hữu'
      });
    }

    const task = await Task.create({
      ...taskData,
      owner: owner._id
    });

    await logActivity(task._id, req.userId, 'admin_created');
    return res.status(201).json({
      message: 'Admin thêm công việc thành công',
      task
    });
  } catch (error) {
    console.error('Admin create task error:', error.message);

    return res.status(500).json({
      message: 'Không thể thêm công việc'
    });
  }
});

// ===== ADMIN: SỬA CÔNG VIỆC =====
app.put('/api/admin/tasks/:id', authenticate, requireAdmin, async (req, res) => {
  try {
    const taskId = req.params.id;

    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({
        message: 'Mã công việc không hợp lệ'
      });
    }

    const existingTask = await Task.findById(taskId);

    if (!existingTask) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc'
      });
    }

    let taskData;

    try {
      taskData = validateTaskInput(req.body, true);
    } catch (error) {
      return res.status(400).json({
        message: error.message
      });
    }

    const newStart = taskData.startDate === undefined ? existingTask.startDate : taskData.startDate;
    const newDue = taskData.dueDate === undefined ? existingTask.dueDate : taskData.dueDate;
    if (newStart && newDue && newStart > newDue) {
      return res.status(400).json({ message: 'Ngày bắt đầu không được sau hạn hoàn thành' });
    }
    const task = await Task.findByIdAndUpdate(
      taskId,
      { $set: taskData },
      { returnDocument: 'after', runValidators: true }
    );

    await logActivity(task._id, req.userId, 'admin_updated');
    return res.status(200).json({
      message: 'Admin sửa công việc thành công',
      task
    });
  } catch (error) {
    console.error('Admin update task error:', error.message);

    return res.status(500).json({
      message: 'Không thể sửa công việc'
    });
  }
});

// ===== ADMIN: XÓA CÔNG VIỆC =====
app.delete('/api/admin/tasks/:id', authenticate, requireAdmin, async (req, res) => {
  try {
    const taskId = req.params.id;

    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({
        message: 'Mã công việc không hợp lệ'
      });
    }

    const task = await Task.findById(taskId);

    if (!task) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc'
      });
    }

    // Xóa dữ liệu chia sẻ liên quan
    await TaskShare.deleteMany({ taskId: task._id });
    await Notification.deleteMany({ taskId: task._id });
    await TaskActivity.deleteMany({ taskId: task._id });

    // Xóa công việc
    await Task.findByIdAndDelete(taskId);

    return res.status(200).json({
      message: 'Admin xóa công việc thành công'
    });
  } catch (error) {
    console.error('Admin delete task error:', error.message);

    return res.status(500).json({
      message: 'Không thể xóa công việc'
    });
  }
});

// ===== ĐĂNG KÝ =====
app.post('/api/register', async (req, res) => {
  try {
    const { fullName, email, password } = req.body || {};

    if (
      typeof fullName !== 'string' ||
      typeof email !== 'string' ||
      typeof password !== 'string'
    ) {
      return res.status(400).json({
        message: 'Thông tin đăng ký không hợp lệ'
      });
    }

    const name = fullName.trim();
    const userEmail = email.trim().toLowerCase();

    if (
      name.length < 2 ||
      name.length > 100 ||
      userEmail.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userEmail)
    ) {
      return res.status(400).json({
        message: 'Họ tên hoặc email không hợp lệ'
      });
    }

    if (password.length < 8 || password.length > 72) {
      return res.status(400).json({
        message: 'Mật khẩu phải có từ 8 đến 72 ký tự'
      });
    }

    const existingUser = await User.findOne({
      email: userEmail
    });

    if (existingUser) {
      return res.status(409).json({
        message: 'Email đã được đăng ký'
      });
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const user = await User.create({
      fullName: name,
      email: userEmail,
      passwordHash
    });

    return res.status(201).json({
      message: 'Đăng ký thành công',
      user: {
        id: user._id.toString(),
        fullName: user.fullName,
        email: user.email
      }
    });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(409).json({
        message: 'Email đã được đăng ký'
      });
    }

    console.error('Register error:', error.message);

    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
});

// ===== ĐĂNG NHẬP =====
app.post('/api/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};

    if (
      typeof email !== 'string' ||
      typeof password !== 'string'
    ) {
      return res.status(400).json({
        message: 'Vui lòng nhập email và mật khẩu'
      });
    }

    const user = await User.findOne({
      email: email.trim().toLowerCase()
    }).select('+passwordHash');

    if (!user) {
      return res.status(401).json({
        message: 'Email hoặc mật khẩu không chính xác'
      });
    }

    const valid = await bcrypt.compare(
      password,
      user.passwordHash
    );

    if (!valid) {
      return res.status(401).json({
        message: 'Email hoặc mật khẩu không chính xác'
      });
    }

    const token = createToken(user);

    return res.json({
      message: 'Đăng nhập thành công',
      token,
      user: {
        id: user._id.toString(),
        fullName: user.fullName,
        email: user.email
      }
    });
  } catch (error) {
    console.error('Login error:', error.message);

    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
 });

  // ===== KIỂM TRA API QUÊN MẬT KHẨU =====
console.log('DA NAP API QUEN MAT KHAU');

 // ===== QUÊN MẬT KHẨU: GỬI MÃ XÁC MINH =====
app.post('/api/auth/forgot-password', async (req, res) => {
  const successMessage =
    'Nếu email đã đăng ký, mã xác minh sẽ được gửi đến email của bạn.';

  try {
    const { email } = req.body || {};

    if (
      typeof email !== 'string' ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
    ) {
      return res.status(400).json({
        message: 'Vui lòng nhập email hợp lệ'
      });
    }

    const normalizedEmail = email.trim().toLowerCase();

    const user = await User.findOne({
      email: normalizedEmail
    }).select('+resetRequestedAt');

    // Không tiết lộ email có tồn tại trong hệ thống hay không
    if (!user) {
      return res.json({ message: successMessage });
    }

    const now = new Date();

    // Mỗi tài khoản chỉ được yêu cầu mã mới sau 60 giây
    if (
      user.resetRequestedAt &&
      now.getTime() -
        new Date(user.resetRequestedAt).getTime() < 60000
    ) {
      return res.json({ message: successMessage });
    }

    // Tạo mã ngẫu nhiên gồm 6 chữ số
    const resetCode = crypto
      .randomInt(0, 1000000)
      .toString()
      .padStart(6, '0');

    // Băm mã bằng khóa bí mật, không lưu mã gốc
    const resetCodeHash = crypto
      .createHmac('sha256', process.env.JWT_SECRET)
      .update(`${user._id}:${resetCode}`)
      .digest('hex');

    user.resetCodeHash = resetCodeHash;
    user.resetCodeExpiresAt = new Date(
      now.getTime() + 10 * 60 * 1000
    );
    user.resetAttempts = 0;
    user.resetRequestedAt = now;

    await user.save();

    // Gửi mã đến email của tài khoản
    try {
      await sendPasswordResetEmail({
        to: user.email,
        recipientName: user.fullName,
        resetCode
      });
    } catch (mailError) {
      console.error(
        'Password reset email error:',
        mailError.message
      );

      // Hủy mã nếu gửi email thất bại
      await User.updateOne(
        {
          _id: user._id,
          resetCodeHash
        },
        {
          $unset: {
            resetCodeHash: '',
            resetCodeExpiresAt: '',
            resetAttempts: '',
            resetRequestedAt: ''
          }
        }
      );
    }

    return res.json({
      message: successMessage
    });

  } catch (error) {
    console.error(
      'Forgot password error:',
      error.message
    );

    return res.status(500).json({
      message: 'Không thể xử lý yêu cầu lúc này'
    });
  }
});

 // ===== XÁC MINH MÃ VÀ ĐẶT LẠI MẬT KHẨU =====
app.post('/api/auth/reset-password', async (req, res) => {
  const invalidMessage =
    'Mã xác minh không hợp lệ, đã hết hạn hoặc vượt quá số lần thử';

  try {
    const { email, resetCode, newPassword } = req.body || {};

    // Kiểm tra dữ liệu nhập
    if (
      typeof email !== 'string' ||
      typeof resetCode !== 'string' ||
      typeof newPassword !== 'string' ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ||
      !/^\d{6}$/.test(resetCode) ||
      newPassword.length < 8 ||
      Buffer.byteLength(newPassword, 'utf8') > 72
    ) {
      return res.status(400).json({
        message:
          'Vui lòng nhập email, mã 6 số và mật khẩu mới từ 8 ký tự hợp lệ'
      });
    }

    const normalizedEmail = email.trim().toLowerCase();

    // Tìm tài khoản và lấy thông tin mã xác minh
    const user = await User.findOne({
      email: normalizedEmail
    }).select(
      '+resetCodeHash +resetCodeExpiresAt +resetAttempts'
    );

    // Không có tài khoản hoặc chưa yêu cầu mã
    if (
      !user ||
      !user.resetCodeHash ||
      !user.resetCodeExpiresAt
    ) {
      return res.status(400).json({
        message: invalidMessage
      });
    }

    const now = new Date();

    // Kiểm tra mã hết hạn hoặc nhập sai quá 5 lần
    if (
      user.resetCodeExpiresAt <= now ||
      (user.resetAttempts || 0) >= 5
    ) {
      return res.status(400).json({
        message: invalidMessage
      });
    }

    // Băm mã người dùng nhập bằng cùng cách với API gửi mã
    const inputCodeHash = crypto
      .createHmac('sha256', process.env.JWT_SECRET)
      .update(`${user._id}:${resetCode}`)
      .digest('hex');

    // So sánh mã xác minh
    const storedHash = Buffer.from(user.resetCodeHash, 'hex');
    const inputHash = Buffer.from(inputCodeHash, 'hex');

    const isValidCode =
      storedHash.length === inputHash.length &&
      crypto.timingSafeEqual(storedHash, inputHash);

    if (!isValidCode) {
      // Tăng số lần nhập sai
      await User.updateOne(
        {
          _id: user._id,
          resetCodeHash: user.resetCodeHash,
          resetAttempts: { $lt: 5 }
        },
        {
          $inc: { resetAttempts: 1 }
        }
      );

      return res.status(400).json({
        message: invalidMessage
      });
    }

    // Mã đúng: mã hóa mật khẩu mới
    const newPasswordHash = await bcrypt.hash(
      newPassword,
      12
    );

    // Chỉ cập nhật nếu mã vẫn còn hiệu lực và chưa bị sử dụng
    const result = await User.updateOne(
      {
        _id: user._id,
        resetCodeHash: user.resetCodeHash,
        resetCodeExpiresAt: { $gt: new Date() },
        resetAttempts: { $lt: 5 }
      },
      {
        $set: {
          passwordHash: newPasswordHash
        },
        $unset: {
          resetCodeHash: '',
          resetCodeExpiresAt: '',
          resetAttempts: '',
          resetRequestedAt: ''
        }
      }
    );

    if (result.modifiedCount !== 1) {
      return res.status(400).json({
        message: invalidMessage
      });
    }

    return res.json({
      message:
        'Đặt lại mật khẩu thành công. Bạn có thể đăng nhập bằng mật khẩu mới.'
    });

  } catch (error) {
    console.error(
      'Reset password error:',
      error.message
    );

    return res.status(500).json({
      message: 'Không thể đặt lại mật khẩu lúc này'
    });
  }
});


// ===== DANH SÁCH NGƯỜI DÙNG ĐỂ PHÂN CÔNG =====
// Chỉ trả về mã và họ tên, không trả email hoặc mật khẩu.
app.get('/api/users', authenticate, async (req, res) => {
  try {
    const users = await User.find({})
      .select('_id fullName email')
      .sort({ fullName: 1 })
      .limit(200)
      .lean();

    return res.json({
      message: 'Lấy danh sách người dùng thành công',
      users
    });
  } catch (error) {
    console.error('List users error:', error.message);
    return res.status(500).json({
      message: 'Không thể tải danh sách người dùng'
    });
  }
});

// ===== PHÂN QUYỀN TRUY CẬP CÔNG VIỆC =====
// owner: toàn quyền; editor: xem/sửa/trạng thái;
// viewer: chỉ xem; assignee: xem và đổi trạng thái (tương thích giao việc cũ).
function isTaskOwner(task, userId) {
  return String(task.owner) === String(userId);
}

function isTaskAssignee(task, userId) {
  const id = String(userId);
  return String(task.assignedTo || '') === id ||
    (task.assigneeIds || []).some(value => String(value) === id);
}

async function getTaskPermission(task, userId) {
  if (isTaskOwner(task, userId)) return 'owner';

  // Quyền chia sẻ tường minh ưu tiên hơn quyền giao việc cũ.
  const share = await TaskShare.findOne({
    taskId: task._id,
    userId
  }).select('permission').lean();

  if (share) return share.permission;
  if (isTaskAssignee(task, userId)) return 'assignee';
  return null;
}

function withTaskPermissions(task, permission) {
  const data = task.toObject ? task.toObject() : task;
  return {
    ...data,
    myPermission: permission,
    canEdit: permission === 'owner' || permission === 'editor',
    canChangeStatus: ['owner', 'editor', 'assignee'].includes(permission),
    canDelete: permission === 'owner',
    canManageShares: permission === 'owner'
  };
}

// ===== DANH SÁCH CÔNG VIỆC + TÌM KIẾM NÂNG CAO =====
app.get('/api/tasks', authenticate, async (req, res) => {
  try {
    // 1. Nhận điều kiện tìm kiếm từ ứng dụng Flutter
    const keyword =
      typeof req.query.q === 'string'
        ? req.query.q.trim()
        : '';

    const status =
      typeof req.query.status === 'string'
        ? req.query.status.trim()
        : '';

    // 2. Kiểm tra dữ liệu tìm kiếm
    if (keyword.length > 100) {
      return res.status(400).json({
        message: 'Từ khóa tìm kiếm quá dài'
      });
    }

    const validStatuses = [
      'pending',
      'in_progress',
      'completed'
    ];

    if (status && !validStatuses.includes(status)) {
      return res.status(400).json({
        message: 'Trạng thái tìm kiếm không hợp lệ'
      });
    }

    // 3. Lấy những công việc được chia sẻ
    const shares = await TaskShare.find({
      userId: req.userId
    })
      .select('taskId permission')
      .lean();

    const sharedIds = shares.map(
      share => share.taskId
    );

    const permissionById = new Map(
      shares.map(share => [
        String(share.taskId),
        share.permission
      ])
    );

    // 4. Giữ nguyên điều kiện phân quyền
    const filter = {
      $or: [
        { owner: req.userId },
        { assignedTo: req.userId },
        { assigneeIds: req.userId },
        { _id: { $in: sharedIds } }
      ]
    };

    // 5. Tìm kiếm theo tên công việc
    if (keyword) {
      const safeKeyword = keyword.replace(
        /[.*+?^${}()|[\]\\]/g,
        '\\$&'
      );

      filter.title = {
        $regex: safeKeyword,
        $options: 'i'
      };
    }

    // 6. Lọc theo trạng thái công việc
    if (status) {
      filter.status = status;
    }

    // 7. Lọc ưu tiên, phạm vi, người phụ trách và sắp xếp
    const priority = typeof req.query.priority === 'string' ? req.query.priority : '';
    const scope = typeof req.query.scope === 'string' ? req.query.scope : '';
    const assigneeId = typeof req.query.assigneeId === 'string' ? req.query.assigneeId : '';
    const sortBy = typeof req.query.sortBy === 'string' ? req.query.sortBy : 'createdAt';
    const order = req.query.order === 'asc' ? 1 : -1;
    if (priority && !['low', 'medium', 'high'].includes(priority)) {
      return res.status(400).json({ message: 'Mức ưu tiên không hợp lệ' });
    }
    if (scope && !['created', 'assigned', 'shared'].includes(scope)) {
      return res.status(400).json({ message: 'Phạm vi không hợp lệ' });
    }
    if (assigneeId && !mongoose.isValidObjectId(assigneeId)) {
      return res.status(400).json({ message: 'Mã người phụ trách không hợp lệ' });
    }
    if (!['createdAt', 'dueDate', 'priority'].includes(sortBy)) {
      return res.status(400).json({ message: 'Kiểu sắp xếp không hợp lệ' });
    }
    if (priority) filter.priority = priority;
    if (assigneeId) filter.$and = [{ $or: [
      { assignedTo: assigneeId }, { assigneeIds: assigneeId },
      { primaryAssigneeId: assigneeId }
    ] }];
    if (scope === 'created') filter.$and = [...(filter.$and || []), { owner: req.userId }];
    if (scope === 'assigned') filter.$and = [...(filter.$and || []), {
      $or: [{ assignedTo: req.userId }, { assigneeIds: req.userId }]
    }];
    if (scope === 'shared') filter.$and = [...(filter.$and || []), { _id: { $in: sharedIds } }];

    // Sắp xếp công việc theo lựa chọn từ Flutter
    let sortOptions;

    if (sortBy === 'createdAt') {
      sortOptions = {
        createdAt: order,
        _id: order
      };
    } else {
      sortOptions = {
        [sortBy]: order,
        createdAt: -1,
        _id: -1
      };
    }

    const tasks = await Task.find(filter)
      .sort(sortOptions)
      .limit(500);


    // 8. Giữ nguyên thông tin phân quyền
    const result = tasks.map(task => {
      let permission = null;

      if (isTaskOwner(task, req.userId)) {
        permission = 'owner';
      } else if (
        permissionById.has(String(task._id))
      ) {
        permission = permissionById.get(
          String(task._id)
        );
      } else if (
        isTaskAssignee(task, req.userId)
      ) {
        permission = 'assignee';
      }

      return withTaskPermissions(
        task,
        permission
      );
    });

    // 9. Trả kết quả cho Flutter
    return res.json({
      message: 'Lấy danh sách công việc thành công',
      tasks: result
    });

  } catch (error) {
    console.error('Tasks error:', error.message);

    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
});


// ===== CHI TIẾT CÔNG VIỆC =====
app.get('/api/tasks/:id', authenticate, async (req, res) => {
  try {
    if (!mongoose.isValidObjectId(req.params.id)) {
      return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
    }

    const task = await Task.findById(req.params.id);
    if (!task) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }

    const permission = await getTaskPermission(task, req.userId);
    if (!permission) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }

    return res.json({
      message: 'Lấy chi tiết công việc thành công',
      task: withTaskPermissions(task, permission)
    });
  } catch (error) {
    console.error('Task detail error:', error.message);
    return res.status(500).json({ message: 'Lỗi máy chủ' });
  }
});

// ===== HÀM KIỂM TRA DỮ LIỆU BUỔI 2 =====

const VALID_STATUSES = [
  'pending',
  'in_progress',
  'completed'
];

function parseDueDate(value) {
  if (value === null || value === '') {
    return null;
  }

  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    throw new Error('Ngày hết hạn phải có dạng YYYY-MM-DD');
  }

  const date = new Date(value + 'T00:00:00.000Z');

  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  ) {
    throw new Error('Ngày hết hạn không hợp lệ');
  }

  return date;
}

function validateTaskInput(body, isUpdate = false) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new Error('Dữ liệu công việc không hợp lệ');
  }

  const { title, description, status, dueDate, startDate, priority } = body;

  if (
    typeof title !== 'string' ||
    title.trim().length < 2 ||
    title.trim().length > 150
  ) {
    throw new Error('Tên công việc phải có từ 2 đến 150 ký tự');
  }

  if (
    description !== undefined &&
    (typeof description !== 'string' || description.length > 2000)
  ) {
    throw new Error('Mô tả công việc không hợp lệ');
  }

  if (
    status !== undefined &&
    !VALID_STATUSES.includes(status)
  ) {
    throw new Error('Trạng thái công việc không hợp lệ');
  }

  if (priority !== undefined && !['low', 'medium', 'high'].includes(priority)) {
    throw new Error('Mức độ ưu tiên không hợp lệ');
  }
  const parsedStart = startDate === undefined ? undefined : parseDueDate(startDate);
  const parsedDue = dueDate === undefined ? undefined : parseDueDate(dueDate);
  if (parsedStart && parsedDue && parsedStart > parsedDue) {
    throw new Error('Ngày bắt đầu không được sau hạn hoàn thành');
  }

  const data = {
    title: title.trim(),
    description: description === undefined
      ? ''
      : description.trim()
  };

  if (status !== undefined) {
    data.status = status;
  } else if (!isUpdate) {
    data.status = 'pending';
  }

  if (dueDate !== undefined) data.dueDate = parsedDue;
  if (startDate !== undefined) data.startDate = parsedStart;
  if (priority !== undefined) data.priority = priority;

  return data;
}


// ===== THÊM CÔNG VIỆC =====
app.post('/api/tasks', authenticate, async (req, res) => {
  try {
    let taskData;

    try {
      taskData = validateTaskInput(req.body);
    } catch (error) {
      return res.status(400).json({
        message: error.message
      });
    }

    const task = await Task.create({
      ...taskData,
      owner: req.userId
    });

    await logActivity(task._id, req.userId, 'created');
    return res.status(201).json({
      message: 'Thêm công việc thành công',
      task
    });
  } catch (error) {
    console.error('Create task error:', error.message);

    return res.status(500).json({
      message: 'Không thể thêm công việc'
    });
  }
});


// ===== SỬA CÔNG VIỆC =====
app.put('/api/tasks/:id', authenticate, async (req, res) => {
  try {
    const taskId = req.params.id;
    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
    }

    const existingTask = await Task.findById(taskId);
    if (!existingTask) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }

    const permission = await getTaskPermission(existingTask, req.userId);
    if (!permission) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }
    if (!['owner', 'editor'].includes(permission)) {
      return res.status(403).json({ message: 'Bạn không có quyền sửa công việc' });
    }

    let taskData;
    try {
      taskData = validateTaskInput(req.body, true);
    } catch (error) {
      return res.status(400).json({ message: error.message });
    }

    const newStart = taskData.startDate === undefined ? existingTask.startDate : taskData.startDate;
    const newDue = taskData.dueDate === undefined ? existingTask.dueDate : taskData.dueDate;
    if (newStart && newDue && newStart > newDue) {
      return res.status(400).json({ message: 'Ngày bắt đầu không được sau hạn hoàn thành' });
    }
    const task = await Task.findByIdAndUpdate(
      taskId,
      { $set: taskData },
      { returnDocument: 'after', runValidators: true }
    );

    await logActivity(task._id, req.userId, 'updated', { fields: Object.keys(taskData) });
    if (taskData.status === 'completed' && existingTask.status !== 'completed') {
      const shared = await TaskShare.find({ taskId }).select('userId').lean();
      void notifyUsers({ userIds: [...taskAudience(task), ...shared.map(x => String(x.userId))]
        .filter(id => id !== String(req.userId)), task,
        type: 'completed', title: 'Công việc hoàn thành',
        message: `Công việc "${task.title}" đã được hoàn thành.` });
    }
    if (taskData.dueDate !== undefined &&
        String(existingTask.dueDate || '') !== String(task.dueDate || '')) {
      const shared = await TaskShare.find({ taskId }).select('userId').lean();
      void notifyUsers({ userIds: [...taskAudience(task), ...shared.map(x => String(x.userId))]
        .filter(id => id !== String(req.userId)), task,
        type: 'deadline_changed', title: 'Thay đổi hạn hoàn thành',
        message: `Hạn hoàn thành công việc "${task.title}" đã thay đổi.` });
    }
    return res.json({
      message: 'Cập nhật công việc thành công',
      task: withTaskPermissions(task, permission)
    });
  } catch (error) {
    console.error('Update task error:', error.message);
    return res.status(500).json({ message: 'Không thể cập nhật công việc' });
  }
});

// ===== XÓA CÔNG VIỆC =====
app.delete('/api/tasks/:id', authenticate, async (req, res) => {
  try {
    const taskId = req.params.id;
    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
    }

    // Chỉ chủ sở hữu được xóa công việc.
    const task = await Task.findOneAndDelete({
      _id: taskId,
      owner: req.userId
    });
    if (!task) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc hoặc không có quyền xóa'
      });
    }

    // Xóa quyền chia sẻ đi kèm để không để lại dữ liệu mồ côi.
    await TaskShare.deleteMany({ taskId: task._id });
    await Notification.deleteMany({ taskId: task._id });
    await TaskActivity.deleteMany({ taskId: task._id });

    return res.json({ message: 'Xóa công việc thành công' });
  } catch (error) {
    console.error('Delete task error:', error.message);
    return res.status(500).json({ message: 'Không thể xóa công việc' });
  }
});

// ===== CẬP NHẬT TRẠNG THÁI =====
app.patch('/api/tasks/:id/status', authenticate, async (req, res) => {
  try {
    const taskId = req.params.id;
    const { status } = req.body || {};

    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
    }
    if (!VALID_STATUSES.includes(status)) {
      return res.status(400).json({ message: 'Trạng thái không hợp lệ' });
    }

    const existingTask = await Task.findById(taskId);
    if (!existingTask) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }

    const permission = await getTaskPermission(existingTask, req.userId);
    if (!permission) {
      return res.status(404).json({ message: 'Không tìm thấy công việc' });
    }
    if (!['owner', 'editor', 'assignee'].includes(permission)) {
      return res.status(403).json({
        message: 'Bạn chỉ có quyền xem, không được cập nhật trạng thái'
      });
    }

    const task = await Task.findByIdAndUpdate(
      taskId,
      { $set: { status } },
      { returnDocument: 'after', runValidators: true }
    );

    await logActivity(task._id, req.userId, 'status_changed', {
      from: existingTask.status, to: status
    });
    if (status === 'completed' && existingTask.status !== 'completed') {
      const shared = await TaskShare.find({ taskId }).select('userId').lean();
      void notifyUsers({ userIds: [...taskAudience(task), ...shared.map(x => String(x.userId))]
        .filter(id => id !== String(req.userId)), task,
        type: 'completed', title: 'Công việc hoàn thành',
        message: `Công việc "${task.title}" đã được hoàn thành.` });
    }
    return res.json({
      message: 'Cập nhật trạng thái thành công',
      task: withTaskPermissions(task, permission)
    });
  } catch (error) {
    console.error('Update status error:', error.message);
    return res.status(500).json({ message: 'Không thể cập nhật trạng thái' });
  }
});

// ===== GIAO CÔNG VIỆC CHO NHIỀU NGƯỜI =====
app.put('/api/tasks/:id/assignees', authenticate, async (req, res) => {
  try {
    const taskId = req.params.id;
    const { userIds, primaryAssigneeId } = req.body || {};

    if (!mongoose.isValidObjectId(taskId)) {
      return res.status(400).json({
        message: 'Mã công việc không hợp lệ'
      });
    }

    if (
      !Array.isArray(userIds) ||
      userIds.length > 20 ||
      !userIds.every(id =>
        typeof id === 'string' &&
        mongoose.isValidObjectId(id)
      )
    ) {
      return res.status(400).json({
        message: 'Danh sách người được giao không hợp lệ'
      });
    }


// Chuẩn hóa danh sách ID được gửi từ Flutter
const requestedIds = [...new Set(
  userIds.map(id => id.toLowerCase())
)];

// Chỉ chủ sở hữu được phân công công việc
const task = await Task.findOne({
  _id: taskId,
  owner: req.userId
});

if (!task) {
  return res.status(404).json({
    message: 'Không tìm thấy công việc hoặc không có quyền giao việc'
  });
}

// Kiểm tra tài khoản thực sự tồn tại trong MongoDB
const users = await User.find({
  _id: { $in: requestedIds }
}).select('_id fullName email');

const existingIds = new Set(
  users.map(user => String(user._id).toLowerCase())
);

// Chỉ giữ những tài khoản còn tồn tại
const uniqueIds = requestedIds.filter(
  id => existingIds.has(id)
);

// Ghi nhận những tài khoản không còn tồn tại
const missingIds = requestedIds.filter(
  id => !existingIds.has(id)
);

if (missingIds.length > 0) {
  console.warn(
    'Các tài khoản không tồn tại:',
    missingIds
  );
}

// Tránh xóa hết phân công khi toàn bộ ID gửi lên đều sai
if (requestedIds.length > 0 && uniqueIds.length === 0) {
  return res.status(400).json({
    message: 'Danh sách phân công không còn tài khoản hợp lệ. Vui lòng tải lại danh sách người dùng.'
  });
}

// Danh sách người được phân công trước đó
const oldAssigneeIds = new Set(
  (task.assigneeIds || []).map(
    id => String(id).toLowerCase()
  )
);

// Chỉ thông báo cho người mới được phân công và còn tồn tại
const newAssigneeIds = new Set(
  uniqueIds.filter(
    id => !oldAssigneeIds.has(id)
  )
);

// Xác định người phụ trách chính hợp lệ
let primaryId = null;

if (uniqueIds.length > 0) {
  const requestedPrimary =
    typeof primaryAssigneeId === 'string'
      ? primaryAssigneeId.toLowerCase()
      : '';

  const oldPrimary =
    String(task.primaryAssigneeId || '').toLowerCase();

  if (uniqueIds.includes(requestedPrimary)) {
    primaryId = requestedPrimary;
  } else if (uniqueIds.includes(oldPrimary)) {
    primaryId = oldPrimary;
  } else {
    primaryId = uniqueIds[0];
  }
}

    task.assigneeIds = uniqueIds;
    task.primaryAssigneeId = primaryId;

    // Đồng bộ trường cũ để các màn hình và API cũ vẫn đọc được.
    task.assignedTo = primaryId;


await task.save();

await logActivity(task._id, req.userId, 'assigned', { userIds: uniqueIds, primaryId });
if (newAssigneeIds.size > 0) {
  void notifyUsers({ userIds: [...newAssigneeIds], task,
    type: 'assigned', title: 'Được giao công việc',
    message: `Bạn được phân công công việc: ${task.title}` });
}

return res.json({
  message: 'Giao công việc thành công',
  task: withTaskPermissions(task, 'owner')
});

  } catch (error) {
    console.error('Assign task error:', error.message);
    return res.status(500).json({
      message: 'Không thể giao công việc'
    });
  }
});

// ===== CHIA SẺ CÔNG VIỆC =====
 // Chỉ chủ công việc được quản lý chia sẻ

async function checkTaskOwner(taskId, userId) {
  if (!mongoose.isValidObjectId(taskId)) {
    return false;
  }

  return !!(await Task.exists({
    _id: taskId,
    owner: userId
  }));
}

// 1. XEM DANH SÁCH NGƯỜI ĐƯỢC CHIA SẺ
app.get('/api/tasks/:id/shares', authenticate, async (req, res) => {
  try {
    const { id } = req.params;

    if (!await checkTaskOwner(id, req.userId)) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc hoặc không có quyền'
      });
    }

    const shares = await TaskShare.find({ taskId: id })
      .populate('userId', 'fullName email')
      .sort({ createdAt: -1 });

    return res.json({ shares });
  } catch (error) {
    console.error('List shares error:', error.message);
    return res.status(500).json({
      message: 'Không thể tải danh sách chia sẻ'
    });
  }
});

// 2. CHIA SẺ CHO MỘT HOẶC NHIỀU NGƯỜI
app.post('/api/tasks/:id/shares', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { shares } = req.body || {};

    if (!await checkTaskOwner(id, req.userId)) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc hoặc không có quyền'
      });
    }

    if (
      !Array.isArray(shares) ||
      shares.length === 0 ||
      shares.length > 20
    ) {
      return res.status(400).json({
        message: 'Danh sách chia sẻ phải có từ 1 đến 20 người'
      });
    }

    const userIds = shares.map(item => item?.userId);

    if (
      shares.some(item =>
        !item ||
        !mongoose.isValidObjectId(item.userId) ||
        !['viewer', 'editor'].includes(item.permission)
      ) ||
      new Set(userIds.map(String)).size !== userIds.length ||
      userIds.some(userId =>
        String(userId) === String(req.userId)
      )
    ) {
      return res.status(400).json({
        message: 'Thông tin chia sẻ không hợp lệ'
      });
    }

    const count = await User.countDocuments({
      _id: { $in: userIds }
    });

    if (count !== userIds.length) {
      return res.status(400).json({
        message: 'Có người dùng không tồn tại'
      });
    }

    const existingShares = await TaskShare.find({
      taskId: id, userId: { $in: userIds }
    }).select('userId').lean();
    const existingShareIds = new Set(existingShares.map(x => String(x.userId)));

    await TaskShare.bulkWrite(
      shares.map(item => ({
        updateOne: {
          filter: {
            taskId: id,
            userId: item.userId
          },
          update: {
            $set: {
              permission: item.permission,
              sharedBy: req.userId
            }
          },
          upsert: true
        }
      }))
    );

    const task = await Task.findById(id);
    await logActivity(id, req.userId, 'shared', { userIds });
    const newShareIds = userIds.filter(userId => !existingShareIds.has(String(userId)));
    if (newShareIds.length) {
      void notifyUsers({ userIds: newShareIds, task,
        type: 'shared', title: 'Được chia sẻ công việc',
        message: `Bạn được mời tham gia công việc: ${task.title}` });
    }
    return res.json({
      message: 'Chia sẻ công việc thành công'
    });
  } catch (error) {
    console.error('Share task error:', error.message);
    return res.status(500).json({
      message: 'Không thể chia sẻ công việc'
    });
  }
});

// 3. THAY ĐỔI QUYỀN VIEWER / EDITOR
app.patch(
  '/api/tasks/:id/shares/:shareId',
  authenticate,
  async (req, res) => {
    try {
      const { id, shareId } = req.params;
      const { permission } = req.body || {};

      if (
        !mongoose.isValidObjectId(shareId) ||
        !['viewer', 'editor'].includes(permission)
      ) {
        return res.status(400).json({
          message: 'Thông tin quyền không hợp lệ'
        });
      }

      // Chỉ chủ công việc được thay đổi quyền
      if (!await checkTaskOwner(id, req.userId)) {
        return res.status(404).json({
          message: 'Không tìm thấy công việc hoặc không có quyền'
        });
      }

      // Tìm quyền chia sẻ hiện tại
      const share = await TaskShare.findOne({
        _id: shareId,
        taskId: id
      });

      if (!share) {
        return res.status(404).json({
          message: 'Không tìm thấy quyền chia sẻ'
        });
      }

      // Lưu quyền cũ để so sánh
      const oldPermission = share.permission;

      // Chỉ cập nhật và gửi email nếu quyền thực sự thay đổi
      if (oldPermission !== permission) {
        share.permission = permission;
        await share.save();

        // Ghi lịch sử thay đổi quyền
        await logActivity(
          id,
          req.userId,
          'permission_changed',
          {
            shareId,
            from: oldPermission,
            to: permission
          }
        );

        // Lấy thông tin công việc
        const task = await Task.findById(id);

        if (task) {
          const permissionLabel =
            permission === 'editor'
              ? 'Chỉnh sửa'
              : 'Chỉ xem';

          // Gửi thông báo và email đến người được đổi quyền
          await notifyUsers({
            userIds: [String(share.userId)],
            task,
            type: 'permission_changed',
            title: 'Thay đổi quyền công việc',
            message:
              `Quyền của bạn đối với công việc "${task.title}" ` +
              `đã được thay đổi thành: ${permissionLabel}.`
          });
        }
      }

      return res.json({
        message: 'Cập nhật quyền thành công',
        share
      });

    } catch (error) {
      console.error(
        'Update share error:',
        error.message
      );

      return res.status(500).json({
        message: 'Không thể cập nhật quyền'
      });
    }
  }
);

// 4. THU HỒI QUYỀN CHIA SẺ
app.delete('/api/tasks/:id/shares/:shareId',
  authenticate,
  async (req, res) => {
    try {
      const { id, shareId } = req.params;

      if (!mongoose.isValidObjectId(shareId)) {
        return res.status(400).json({
          message: 'Mã chia sẻ không hợp lệ'
        });
      }

      if (!await checkTaskOwner(id, req.userId)) {
        return res.status(404).json({
          message: 'Không tìm thấy công việc hoặc không có quyền'
        });
      }

      const share = await TaskShare.findOneAndDelete({
        _id: shareId,
        taskId: id
      });

      if (!share) {
        return res.status(404).json({
          message: 'Không tìm thấy quyền chia sẻ'
        });
      }


await logActivity(
  id,
  req.userId,
  'share_revoked',
  { shareId, userId: String(share.userId) }
);

// Lấy thông tin công việc vừa thu hồi quyền
const task = await Task.findById(id);

if (task) {
  // Gửi thông báo đến người vừa bị thu hồi quyền
  await notifyUsers({
    userIds: [String(share.userId)],
    task,
    type: 'share_revoked',
    title: 'Thu hồi quyền chia sẻ',
    message:
      `Quyền truy cập của bạn đối với công việc ` +
      `"${task.title}" đã được thu hồi.`
  });
}

return res.json({
  message: 'Thu hồi quyền chia sẻ thành công'
});

    } catch (error) {
      console.error('Delete share error:', error.message);
      return res.status(500).json({
        message: 'Không thể thu hồi quyền'
      });
    }
  }
);


// ===== HỒ SƠ CÁ NHÂN =====
app.get('/api/auth/me', authenticate, async (req, res) => {
  try {
    const user = await User.findById(req.userId).select('_id fullName email role createdAt');
    if (!user) return res.status(404).json({ message: 'Không tìm thấy tài khoản' });
    return res.json({ user });
  } catch (error) { return res.status(500).json({ message: 'Lỗi máy chủ' }); }
});

app.put('/api/auth/me', authenticate, async (req, res) => {
  try {
    const fullName = req.body?.fullName;
    if (typeof fullName !== 'string' || fullName.trim().length < 2 || fullName.trim().length > 100)
      return res.status(400).json({ message: 'Họ tên phải có từ 2 đến 100 ký tự' });
    const user = await User.findByIdAndUpdate(req.userId,
      { $set: { fullName: fullName.trim() } }, { new: true, runValidators: true })
      .select('_id fullName email role');
    return res.json({ message: 'Cập nhật hồ sơ thành công', user });
  } catch (error) { return res.status(500).json({ message: 'Lỗi máy chủ' }); }
});

app.put('/api/auth/change-password', authenticate, async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body || {};
    if (typeof oldPassword !== 'string' || typeof newPassword !== 'string' ||
        newPassword.length < 8 || newPassword.length > 72)
      return res.status(400).json({ message: 'Mật khẩu mới phải có từ 8 đến 72 ký tự' });
    const user = await User.findById(req.userId).select('+passwordHash');
    if (!user || !await bcrypt.compare(oldPassword, user.passwordHash))
      return res.status(400).json({ message: 'Mật khẩu hiện tại không đúng' });
    user.passwordHash = await bcrypt.hash(newPassword, 12);
    await user.save();
    return res.json({ message: 'Đổi mật khẩu thành công' });
  } catch (error) { return res.status(500).json({ message: 'Lỗi máy chủ' }); }
});

// ===== TÌM KIẾM NGƯỜI DÙNG =====
app.get('/api/users/search', authenticate, async (req, res) => {
  try {
    const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
    if (!q || q.length > 100) return res.status(400).json({ message: 'Từ khóa không hợp lệ' });
    const safe = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const users = await User.find({ $or: [
      { fullName: { $regex: safe, $options: 'i' } },
      { email: { $regex: safe, $options: 'i' } }
    ] }).select('_id fullName email').limit(30).lean();
    return res.json({ users });
  } catch (error) { return res.status(500).json({ message: 'Lỗi máy chủ' }); }
});

app.get('/api/users/:id', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã người dùng không hợp lệ' });
  const user = await User.findById(req.params.id).select('_id fullName');
  if (!user) return res.status(404).json({ message: 'Không tìm thấy người dùng' });
  return res.json({ user });
});

// ===== THÔNG BÁO TRONG ỨNG DỤNG =====
app.get('/api/notifications', authenticate, async (req, res) => {
  const notifications = await Notification.find({ userId: req.userId })
    .sort({ createdAt: -1 }).limit(100).lean();
  return res.json({ notifications });
});
app.get('/api/notifications/unread-count', authenticate, async (req, res) => {
  const count = await Notification.countDocuments({ userId: req.userId, isRead: false });
  return res.json({ count });
});
app.patch('/api/notifications/read-all', authenticate, async (req, res) => {
  await Notification.updateMany({ userId: req.userId, isRead: false }, { $set: { isRead: true } });
  return res.json({ message: 'Đã đánh dấu tất cả là đã đọc' });
});
app.patch('/api/notifications/:id/read', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã thông báo không hợp lệ' });
  const notification = await Notification.findOneAndUpdate(
    { _id: req.params.id, userId: req.userId }, { $set: { isRead: true } }, { new: true });
  if (!notification) return res.status(404).json({ message: 'Không tìm thấy thông báo' });
  return res.json({ notification });
});

// ===== LỊCH SỬ HOẠT ĐỘNG VÀ EMAIL =====
app.get('/api/tasks/:id/activities', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
  const task = await Task.findById(req.params.id);
  if (!task || !await getTaskPermission(task, req.userId))
    return res.status(404).json({ message: 'Không tìm thấy công việc' });
  const activities = await TaskActivity.find({ taskId: task._id })
    .sort({ createdAt: -1 }).limit(100).lean();
  return res.json({ activities });
});
app.get('/api/tasks/:id/email-logs', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
  if (!await checkTaskOwner(req.params.id, req.userId))
    return res.status(404).json({ message: 'Không tìm thấy công việc hoặc không có quyền' });
  const logs = await EmailLog.find({ taskId: req.params.id })
    .sort({ createdAt: -1 }).limit(100).lean();
  return res.json({ logs });
});
app.post('/api/email-logs/:id/retry', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã email không hợp lệ' });
  const log = await EmailLog.findById(req.params.id);
  if (!log || log.status !== 'failed' || log.attempts >= 3 ||
      !log.taskId || !await checkTaskOwner(log.taskId, req.userId))
    return res.status(403).json({ message: 'Không thể gửi lại email này' });
  const task = await Task.findById(log.taskId);
  if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc' });
  log.attempts += 1;
  log.status = 'pending';
  await log.save();
  try {
    await sendEventEmail({ to: log.recipientEmail, subject: log.subject,
      message: `Thông báo liên quan công việc: ${task.title}` });
    log.status = 'sent'; log.sentAt = new Date(); log.errorMessage = '';
  } catch (error) { log.status = 'failed'; log.errorMessage = error.message.slice(0, 500); }
  await log.save();
  return res.json({ message: log.status === 'sent' ? 'Gửi lại thành công' : 'Gửi lại thất bại', log });
});

// ===== THỐNG KÊ THEO QUYỀN =====
async function visibleTaskFilter(userId) {
  const shares = await TaskShare.find({ userId }).select('taskId').lean();
  return { $or: [{ owner: userId }, { assignedTo: userId },
    { assigneeIds: userId }, { _id: { $in: shares.map(x => x.taskId) } }] };
}
app.get('/api/statistics/tasks', authenticate, async (req, res) => {
  const tasks = await Task.find(await visibleTaskFilter(req.userId)).select('status').lean();
  return res.json({ total: tasks.length,
    pending: tasks.filter(x => x.status === 'pending').length,
    in_progress: tasks.filter(x => x.status === 'in_progress').length,
    completed: tasks.filter(x => x.status === 'completed').length });
});
app.get('/api/statistics/assignments', authenticate, async (req, res) => {
  const assigned = await Task.countDocuments({ $or: [
    { assignedTo: req.userId }, { assigneeIds: req.userId } ] });
  const primary = await Task.countDocuments({ primaryAssigneeId: req.userId });
  const created = await Task.countDocuments({ owner: req.userId });
  return res.json({ assigned, primary, created });
});
app.get('/api/statistics/deadlines', authenticate, async (req, res) => {
  const filter = await visibleTaskFilter(req.userId);
  const today = new Date(); today.setUTCHours(0, 0, 0, 0);
  const soon = new Date(today.getTime() + 7 * 86400000);
  const active = { status: { $ne: 'completed' }, dueDate: { $ne: null } };
  const overdue = await Task.countDocuments({ $and: [filter, active, { dueDate: { $lt: today } }] });
  const upcoming = await Task.countDocuments({ $and: [filter, active,
    { dueDate: { $gte: today, $lte: soon } }] });
  return res.json({ overdue, upcoming, withinDays: 7 });
});

// ===== API GIAO VIỆC THEO CASE STUDY =====
app.get('/api/tasks/:id/assignees', authenticate, async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(400).json({ message: 'Mã công việc không hợp lệ' });
  const task = await Task.findById(req.params.id);
  if (!task || !await getTaskPermission(task, req.userId))
    return res.status(404).json({ message: 'Không tìm thấy công việc' });
  const users = await User.find({ _id: { $in: task.assigneeIds } })
    .select('_id fullName').lean();
  return res.json({ users, primaryAssigneeId: task.primaryAssigneeId });
});

// ===== GIAO VIỆC: THÊM, ĐỔI NGƯỜI PHỤ TRÁCH, HỦY GIAO =====
app.post('/api/tasks/:id/assignees', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const userIds = req.body?.userIds;
    if (!mongoose.isValidObjectId(id) || !Array.isArray(userIds) ||
        !userIds.length || userIds.length > 20 ||
        userIds.some(x => typeof x !== 'string' || !mongoose.isValidObjectId(x)))
      return res.status(400).json({ message: 'Danh sách người nhận không hợp lệ' });
    const task = await Task.findOne({ _id: id, owner: req.userId });
    if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc không có quyền' });
    const oldIds = new Set((task.assigneeIds || []).map(String));
    const ids = [...new Set([...oldIds, ...userIds.map(String)])];
    if (ids.length > 20) return res.status(400).json({ message: 'Tối đa 20 người được giao' });
    const users = await User.find({ _id: { $in: ids } }).select('_id');
    if (users.length !== ids.length)
      return res.status(400).json({ message: 'Người dùng không tồn tại' });
    task.assigneeIds = ids;
    if (!task.primaryAssigneeId && ids.length) task.primaryAssigneeId = ids[0];
    task.assignedTo = task.primaryAssigneeId;
    await task.save();
    const newlyAssigned = ids.filter(x => !oldIds.has(x));
    await logActivity(task._id, req.userId, 'assigned', { userIds: newlyAssigned });
    if (newlyAssigned.length) void notifyUsers({ userIds: newlyAssigned, task,
      type: 'assigned', title: 'Được giao công việc',
      message: `Bạn được phân công công việc: ${task.title}` });
    return res.json({ message: 'Giao công việc thành công',
      task: withTaskPermissions(task, 'owner') });
  } catch (error) {
    console.error('Add assignees:', error.message);
    return res.status(500).json({ message: 'Không thể giao công việc' });
  }
});

app.patch('/api/tasks/:id/assignees/:userId', authenticate, async (req, res) => {
  try {
    const { id, userId } = req.params;
    if (!mongoose.isValidObjectId(id) || !mongoose.isValidObjectId(userId))
      return res.status(400).json({ message: 'Mã không hợp lệ' });
    if (req.body?.primary !== true)
      return res.status(400).json({ message: 'Dùng primary=true để chọn người phụ trách chính' });
    const task = await Task.findOne({ _id: id, owner: req.userId });
    if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc không có quyền' });
    if (!(task.assigneeIds || []).some(x => String(x) === userId))
      return res.status(400).json({ message: 'Người này chưa được giao công việc' });
    task.primaryAssigneeId = userId;
    task.assignedTo = userId;
    await task.save();
    await logActivity(task._id, req.userId, 'primary_changed', { userId });
    return res.json({ message: 'Đổi người phụ trách chính thành công',
      task: withTaskPermissions(task, 'owner') });
  } catch (error) { return res.status(500).json({ message: 'Không thể đổi người phụ trách' }); }
});

app.delete('/api/tasks/:id/assignees/:userId', authenticate, async (req, res) => {
  try {
    const { id, userId } = req.params;
    if (!mongoose.isValidObjectId(id) || !mongoose.isValidObjectId(userId))
      return res.status(400).json({ message: 'Mã không hợp lệ' });
    const task = await Task.findOne({ _id: id, owner: req.userId });
    if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc không có quyền' });
    task.assigneeIds = (task.assigneeIds || []).filter(x => String(x) !== userId);
    if (String(task.primaryAssigneeId || '') === userId)
      task.primaryAssigneeId = task.assigneeIds.length ? task.assigneeIds[0] : null;
    task.assignedTo = task.primaryAssigneeId;
    await task.save();
    await logActivity(task._id, req.userId, 'unassigned', { userId });
    return res.json({ message: 'Hủy giao việc thành công',
      task: withTaskPermissions(task, 'owner') });
  } catch (error) { return res.status(500).json({ message: 'Không thể hủy giao việc' }); }
});

// ===== KẾT NỐI MONGODB VÀ CHẠY SERVER =====
async function startServer() {
  try {
    if (!process.env.MONGODB_URI) {
      throw new Error('Thiếu MONGODB_URI trong file .env');
    }

    if (
      !process.env.JWT_SECRET ||
      process.env.JWT_SECRET.length < 32
    ) {
      throw new Error('JWT_SECRET phải có ít nhất 32 ký tự');
    }

    await mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 5000
    });

    console.log('Đã kết nối MongoDB thành công!');

    app.listen(PORT, '0.0.0.0', () => {
      console.log(
        `Backend đang chạy tại http://localhost:${PORT}`
      );
    });
  } catch (error) {
    console.error('Không thể khởi động Backend:', error.message);
    process.exit(1);
  }
}

startServer();
