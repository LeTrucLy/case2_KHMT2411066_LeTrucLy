const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 465),
  secure: Number(process.env.SMTP_PORT || 465) === 465,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});

async function sendEventEmail({ to, recipientName, subject, message }) {
  if (!to || !subject || !message) throw new Error('Thiếu thông tin gửi email');
  return transporter.sendMail({
    from: process.env.SMTP_FROM,
    to,
    subject,
    text: `Xin chào ${recipientName || 'bạn'},\n\n${message}\n\nHãy đăng nhập Task Manager để xem chi tiết.\n\nTask Manager`
  });
}

async function sendAssignmentEmail({ to, recipientName, taskTitle }) {
  return sendEventEmail({ to, recipientName,
    subject: 'Task Manager - Thông báo phân công công việc',
    message: `Bạn vừa được phân công công việc: ${taskTitle}` });
}

 // ===== GỬI MÃ KHÔI PHỤC MẬT KHẨU =====
async function sendPasswordResetEmail({
  to,
  recipientName,
  resetCode
}) {
  if (!to || !/^\d{6}$/.test(String(resetCode))) {
    throw new Error('Thông tin khôi phục mật khẩu không hợp lệ');
  }

  return sendEventEmail({
    to,
    recipientName,
    subject: 'Task Manager - Mã khôi phục mật khẩu',
    message:
      `Bạn đã yêu cầu đặt lại mật khẩu Task Manager.\n\n` +
      `Mã xác minh của bạn là: ${resetCode}\n\n` +
      `Mã có hiệu lực trong 10 phút.\n` +
      `Không chia sẻ mã này với bất kỳ ai.\n\n` +
      `Nếu bạn không yêu cầu đổi mật khẩu, ` +
      `hãy bỏ qua email này.`
  });
}

module.exports = {
  sendAssignmentEmail,
  sendEventEmail,
  sendPasswordResetEmail
};
