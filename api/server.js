
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
    owner: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    }
  },
  { timestamps: true }
);

const Task = mongoose.model('Task', taskSchema);

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

// ===== KIỂM TRA SERVER =====
app.get('/', (req, res) => {
  res.json({
    message: 'Task Manager API đang hoạt động!',
    database: 'MongoDB'
  });
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

// ===== DANH SÁCH CÔNG VIỆC =====
app.get('/api/tasks', authenticate, async (req, res) => {
  try {
    const tasks = await Task.find({
      owner: req.userId
    }).sort({ createdAt: -1 });

    return res.json({
      message: 'Lấy danh sách công việc thành công',
      tasks
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
      return res.status(400).json({
        message: 'Mã công việc không hợp lệ'
      });
    }

    const task = await Task.findOne({
      _id: req.params.id,
      owner: req.userId
    });

    if (!task) {
      return res.status(404).json({
        message: 'Không tìm thấy công việc'
      });
    }

    return res.json({
      message: 'Lấy chi tiết công việc thành công',
      task
    });
  } catch (error) {
    console.error('Task detail error:', error.message);

    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
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
