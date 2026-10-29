package com.dsh.space;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * 极简 adb 客户端：连本机 adbd（127.0.0.1:5555），拿一个 shell/root 通道。
 *
 * 本机 adbd 的 ro.adb.secure=0，所以不需要 RSA 认证，直接 CNXN 即可；
 * emulator 上 adbd 以 root 身份运行，因此拿到的 shell 就是 root shell。
 */
final class AdbClient {

    static final int A_CNXN = 0x4e584e43;
    static final int A_AUTH = 0x48545541;
    static final int A_OPEN = 0x4e45504f;
    static final int A_OKAY = 0x59414b4f;
    static final int A_CLSE = 0x45534c43;
    static final int A_WRTE = 0x45545257;

    private Socket sock;
    private InputStream in;
    private OutputStream out;
    private int nextLocalId = 1;

    /** 设置读超时（毫秒）；切用户这类长命令要放大 */
    void setTimeout(int ms) throws IOException {
        if (sock != null) sock.setSoTimeout(ms);
    }

    /** 连接并完成 CNXN 握手，返回 adbd 的 banner（含版本信息） */
    String connect() throws IOException {
        sock = new Socket();
        sock.connect(new InetSocketAddress("127.0.0.1", 5555), 4000);
        sock.setSoTimeout(8000);
        in = sock.getInputStream();
        out = sock.getOutputStream();

        send(A_CNXN, 0x01000000, 4096, "host::\u0000".getBytes("UTF-8"));

        long deadline = System.currentTimeMillis() + 6000;
        while (System.currentTimeMillis() < deadline) {
            Msg m = read();
            if (m == null) break;
            if (m.cmd == A_CNXN) {
                return new String(m.data, "UTF-8");
            }
            if (m.cmd == A_AUTH) {
                throw new IOException("adbd 要求认证（ro.adb.secure=1），本机不支持");
            }
        }
        throw new IOException("握手超时：没收到 CNXN");
    }

    void close() {
        try { if (sock != null) sock.close(); } catch (IOException ignored) { }
        sock = null;
    }

    /** 执行一条 shell 命令，返回 stdout+stderr 合并文本 */
    String shell(String cmd) {
        StringBuilder sb = new StringBuilder();
        int localId = nextLocalId++;
        try {
            send(A_OPEN, localId, 0, ("shell:" + cmd + "\u0000").getBytes("UTF-8"));
            long deadline = System.currentTimeMillis() + 20000;
            boolean opened = false;
            int remoteId = 0;
            while (System.currentTimeMillis() < deadline) {
                Msg m = read();
                if (m == null) break;
                if (m.cmd == A_OKAY) {
                    if (m.arg1 == localId) {
                        opened = true;
                        remoteId = m.arg0;
                    }
                } else if (m.cmd == A_WRTE) {
                    if (m.arg1 == localId) {
                        if (m.remoteId != 0) remoteId = m.remoteId;
                        sb.append(new String(m.data, "UTF-8"));
                        send(A_OKAY, localId, remoteId, new byte[0]);
                    }
                } else if (m.cmd == A_CLSE) {
                    if (m.arg1 == localId || m.arg0 == remoteId) break;
                }
            }
            try { send(A_CLSE, localId, remoteId, new byte[0]); } catch (IOException ignored) { }
            if (!opened && sb.length() == 0) return "[打开 shell 通道失败]";
            return sb.toString();
        } catch (Exception e) {
            return "[adb 执行失败: " + e + "]";
        }
    }

    // ------------- 协议 -------------

    static final class Msg {
        int cmd, arg0, arg1, remoteId;
        byte[] data;
    }

    private void send(int cmd, int arg0, int arg1, byte[] data) throws IOException {
        ByteBuffer b = ByteBuffer.allocate(24 + data.length).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(cmd).putInt(arg0).putInt(arg1).putInt(data.length).putInt(0).putInt(cmd ^ 0xffffffff);
        b.put(data);
        out.write(b.array());
        out.flush();
    }

    private Msg read() throws IOException {
        byte[] h = new byte[24];
        if (readFully(h) < 0) return null;
        ByteBuffer b = ByteBuffer.wrap(h).order(ByteOrder.LITTLE_ENDIAN);
        Msg m = new Msg();
        m.cmd = b.getInt();
        m.arg0 = b.getInt();
        m.arg1 = b.getInt();
        int len = b.getInt();
        b.getInt(); // crc
        b.getInt(); // magic
        if (len < 0 || len > 1024 * 1024) throw new IOException("非法长度 " + len);
        m.data = new byte[len];
        if (len > 0 && readFully(m.data) < 0) return null;
        m.remoteId = (m.cmd == A_WRTE || m.cmd == A_CLSE) ? m.arg0 : 0;
        return m;
    }

    private int readFully(byte[] buf) throws IOException {
        int off = 0;
        while (off < buf.length) {
            int n = in.read(buf, off, buf.length - off);
            if (n < 0) return -1;
            off += n;
        }
        return off;
    }

    /** 一次性执行：连接 → 运行 → 断开 */
    static String run(String cmd) {
        AdbClient c = new AdbClient();
        try {
            c.connect();
            return c.shell(cmd);
        } catch (Exception e) {
            return "[adb 连接失败: " + e + "]";
        } finally {
            c.close();
        }
    }

    /** 取末行非空输出，用于日志 */
    static String tail(String out) {
        if (out == null) return "";
        String last = "";
        for (String l : out.split("\n")) {
            if (!l.trim().isEmpty()) last = l.trim();
        }
        return last.length() > 70 ? last.substring(0, 70) + "…" : last;
    }

    /** 取首行非空输出，用于日志 */
    static String brief(String out) {
        if (out == null) return "";
        for (String l : out.split("\n")) {
            String t = l.trim();
            if (!t.isEmpty()) {
                if (t.length() > 70) t = t.substring(0, 70) + "…";
                return t;
            }
        }
        return "(无输出)";
    }
}
