
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const Database = require('better-sqlite3');
const path = require('path');

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json({ limit: '20kb' }));

// Khởi tạo cơ sở dữ liệu
const db = new Database(
  path.join(__dirname, 'task_manager.db')
);

db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )
`);

// Kiểm tra Backend
app.get('/', (req, res) => {
  res.json({
    message: 'Task Manager API đang hoạt động!'
  });
});

// API đăng ký
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

    if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userEmail)) {
      return res.status(400).json({
        message: 'Họ tên hoặc email không hợp lệ'
      });
    }

    if (password.length < 8 || password.length > 72) {
      return res.status(400).json({
        message: 'Mật khẩu phải có từ 8 đến 72 ký tự'
      });
    }

    const existingUser = db.prepare(
      'SELECT id FROM users WHERE email = ?'
    ).get(userEmail);

    if (existingUser) {
      return res.status(409).json({
        message: 'Email đã được đăng ký'
      });
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const result = db.prepare(`
      INSERT INTO users (full_name, email, password_hash)
      VALUES (?, ?, ?)
    `).run(name, userEmail, passwordHash);

    return res.status(201).json({
      message: 'Đăng ký thành công',
      user: {
        id: Number(result.lastInsertRowid),
        fullName: name,
        email: userEmail
      }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json({
        message: 'Email đã được đăng ký'
      });
    }

    console.error(error);
    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
});

// API đăng nhập
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

    const user = db.prepare(
      'SELECT * FROM users WHERE email = ?'
    ).get(email.trim().toLowerCase());

    if (!user) {
      return res.status(401).json({
        message: 'Email hoặc mật khẩu không chính xác'
      });
    }

    const valid = await bcrypt.compare(
      password,
      user.password_hash
    );

    if (!valid) {
      return res.status(401).json({
        message: 'Email hoặc mật khẩu không chính xác'
      });
    }

    return res.json({
      message: 'Đăng nhập thành công',
      user: {
        id: user.id,
        fullName: user.full_name,
        email: user.email
      }
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Backend đang chạy tại http://localhost:${PORT}`);
});
