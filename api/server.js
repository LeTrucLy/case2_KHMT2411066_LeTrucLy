require('dotenv').config();

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');

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
    dueDate: {
      type: Date,
      default: null
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

    const task = await Task.findByIdAndUpdate(
      taskId,
      { $set: taskData },
      { returnDocument: 'after', runValidators: true }
    );

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

// ===== DANH SÁCH NGƯỜI DÙNG ĐỂ PHÂN CÔNG =====
// Chỉ trả về mã và họ tên, không trả email hoặc mật khẩu.
app.get('/api/users', authenticate, async (req, res) => {
  try {
    const users = await User.find({})
      .select('_id fullName')
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

// ===== DANH SÁCH CÔNG VIỆC =====
app.get('/api/tasks', authenticate, async (req, res) => {
  try {
    const shares = await TaskShare.find({ userId: req.userId })
      .select('taskId permission')
      .lean();
    const sharedIds = shares.map(share => share.taskId);
    const permissionById = new Map(
      shares.map(share => [String(share.taskId), share.permission])
    );

    const tasks = await Task.find({
      $or: [
        { owner: req.userId },
        { assignedTo: req.userId },
        { assigneeIds: req.userId },
        { _id: { $in: sharedIds } }
      ]
    }).sort({ createdAt: -1 });

    const result = tasks.map(task => {
      let permission = null;
      if (isTaskOwner(task, req.userId)) {
        permission = 'owner';
      } else if (permissionById.has(String(task._id))) {
        permission = permissionById.get(String(task._id));
      } else if (isTaskAssignee(task, req.userId)) {
        permission = 'assignee';
      }
      return withTaskPermissions(task, permission);
    });

    return res.json({
      message: 'Lấy danh sách công việc thành công',
      tasks: result
    });
  } catch (error) {
    console.error('Tasks error:', error.message);
    return res.status(500).json({ message: 'Lỗi máy chủ' });
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

  const { title, description, status, dueDate } = body;

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

  if (dueDate !== undefined) {
    data.dueDate = parseDueDate(dueDate);
  }

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

    const task = await Task.findByIdAndUpdate(
      taskId,
      { $set: taskData },
      { returnDocument: 'after', runValidators: true }
    );

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
    const { userIds } = req.body || {};

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

    const uniqueIds = [...new Set(
      userIds.map(id => id.toLowerCase())
    )];

    const task = await Task.findOne({
      _id: taskId,
      owner: req.userId
    });

    if (!task) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc hoặc không có quyền giao việc'
      });
    }

    const users = await User.find({
      _id: { $in: uniqueIds }
    }).select('_id');

    if (users.length !== uniqueIds.length) {
      return res.status(400).json({
        message: 'Có tài khoản được giao không tồn tại'
      });
    }

    task.assigneeIds = uniqueIds;
    task.primaryAssigneeId = uniqueIds[0] || null;

    // Đồng bộ với trường cũ
    task.assignedTo = uniqueIds[0] || null;

    await task.save();

    return res.json({
      message: 'Giao công việc thành công',
      task
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

      if (!await checkTaskOwner(id, req.userId)) {
        return res.status(404).json({
          message: 'Không tìm thấy công việc hoặc không có quyền'
        });
      }

      const share = await TaskShare.findOneAndUpdate(
        { _id: shareId, taskId: id },
        { $set: { permission } },
        { new: true, runValidators: true }
      );

      if (!share) {
        return res.status(404).json({
          message: 'Không tìm thấy quyền chia sẻ'
        });
      }

      return res.json({
        message: 'Cập nhật quyền thành công',
        share
      });
    } catch (error) {
      console.error('Update share error:', error.message);
      return res.status(500).json({
        message: 'Không thể cập nhật quyền'
      });
    }
  }
);

// 4. THU HỒI QUYỀN CHIA SẺ
app.delete(
  '/api/tasks/:id/shares/:shareId',
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

