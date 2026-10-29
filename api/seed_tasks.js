
require('dotenv').config();

const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  fullName: String,
  email: String,
  passwordHash: String
});

const taskSchema = new mongoose.Schema({
  title: String,
  description: String,
  status: String,
  owner: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  }
}, { timestamps: true });

const User = mongoose.model('User', userSchema);
const Task = mongoose.model('Task', taskSchema);

async function seedTasks() {
  try {
    const email = process.argv[2]?.trim().toLowerCase();

    if (!email) {
      console.log('Vui lòng nhập email tài khoản đã đăng ký.');
      console.log('Ví dụ: node seed_tasks.js email@example.com');
      process.exitCode = 1;
      return;
    }

    if (!process.env.MONGODB_URI) {
      throw new Error('Chưa có MONGODB_URI trong file .env');
    }

    await mongoose.connect(process.env.MONGODB_URI);

    const user = await User.findOne({ email });

    if (!user) {
      console.log('Không tìm thấy tài khoản trong MongoDB.');
      process.exitCode = 1;
      return;
    }

    const sampleTasks = [
      {
        title: 'Hoàn thành bài thực hành Flutter',
        description: 'Xây dựng ứng dụng Task Manager - Buổi 1',
        status: 'pending'
      },
      {
        title: 'Thiết kế giao diện đăng nhập',
        description: 'Hoàn thiện màn hình đăng nhập và đăng ký',
        status: 'completed'
      },
      {
        title: 'Kết nối Flutter với Node.js',
        description: 'Gọi API và xử lý dữ liệu trả về',
        status: 'completed'
      },
      {
        title: 'Kết nối cơ sở dữ liệu MongoDB',
        description: 'Lưu tài khoản và truy vấn công việc',
        status: 'in_progress'
      },
      {
        title: 'Kiểm tra chi tiết công việc',
        description: 'Mở một công việc và xem thông tin chi tiết',
        status: 'pending'
      }
    ];

    // Chỉ tạo dữ liệu mẫu nếu tài khoản chưa có công việc.
    const existingCount = await Task.countDocuments({
      owner: user._id
    });

    if (existingCount > 0) {
      console.log(
        `Tài khoản đã có ${existingCount} công việc. Không thêm trùng.`
      );
      return;
    }

    await Task.insertMany(
      sampleTasks.map(task => ({
        ...task,
        owner: user._id
      }))
    );

    console.log('Đã thêm thành công 5 công việc mẫu!');
  } catch (error) {
    console.error('Lỗi tạo dữ liệu mẫu:', error.message);
    process.exitCode = 1;
  } finally {
    await mongoose.disconnect();
  }
}

seedTasks();
