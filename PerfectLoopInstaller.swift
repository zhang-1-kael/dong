import Foundation

/// 安装失败原因（Result 要求 Failure 符合 Error）
struct PerfectLoopInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// PerfectLoop 插件 · App 内一键安装器
///
/// 目标：用户点一下按钮就装好并立即生效，全程不用离开 App、不用右键打开、不用重启。
/// 流程：下载安装包 zip → 解压到临时目录 → 静默跑安装脚本（装 uv/venv/依赖 + 部署源码 + 自检）
///       → 成功后清 Transcoder 的运行时缓存（插件发现是懒加载，清了就即时生效）。
///
/// 说明：App 为 ad-hoc 签名、无沙箱，可自由跑 Process / 写 ~/.local/share（与转码器一致）。
/// 所有 UI 回调都切回主线程。
final class PerfectLoopInstaller {

    static let shared = PerfectLoopInstaller()
    private init() {}

    private(set) var isInstalling = false
    private var currentProcess: Process?
    private var cancelled = false

    /// 开始安装。
    /// - progress: 主线程回调，参数是给人看的一步进度文字
    /// - finished: 主线程回调，成功 .success，失败 .failure(原因)
    func install(progress: @escaping (String) -> Void,
                 finished: @escaping (Result<Void, PerfectLoopInstallError>) -> Void) {
        guard !isInstalling else {
            finished(.failure(PerfectLoopInstallError(message: "正在安装中，请稍候")))
            return
        }
        isInstalling = true
        cancelled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("vw-perfectloop-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            // 1) 下载安装包
            self.emit(progress, "正在下载插件包…")
            let zipURL = tmp.appendingPathComponent("plugin.zip")
            guard self.download(Transcoder.perfectLoopInstallURL, to: zipURL) else {
                self.finish(finished, .failure(PerfectLoopInstallError(message: "下载失败，请检查网络后重试")))
                return
            }
            guard !self.cancelled else { self.finishCancelled(finished); return }

            // 2) 解压
            self.emit(progress, "正在解压…")
            guard self.run("/usr/bin/unzip", ["-oq", zipURL.path, "-d", tmp.path]) == 0 else {
                self.finish(finished, .failure(PerfectLoopInstallError(message: "解压失败，安装包可能不完整")))
                return
            }
            let runner = tmp.appendingPathComponent("perfectloop_runner.py")
            let src = tmp.appendingPathComponent("PerfectLoop")
            guard FileManager.default.fileExists(atPath: runner.path),
                  FileManager.default.fileExists(atPath: src.path) else {
                self.finish(finished, .failure(PerfectLoopInstallError(message: "安装包缺少插件文件，请重试")))
                return
            }
            guard !self.cancelled else { self.finishCancelled(finished); return }

            // 3) 写静默安装脚本（源自打包的 .command，但去掉两处交互 read）
            let script = tmp.appendingPathComponent("silent_install.sh")
            guard self.writeSilentScript(to: script, tmp: tmp) else {
                self.finish(finished, .failure(PerfectLoopInstallError(message: "无法准备安装脚本")))
                return
            }

            // 4) 执行安装，逐行回进度
            self.emit(progress, "正在安装，首次需下载约 330 MB 依赖，请耐心等待…")
            let code = self.runStreaming("/bin/bash", [script.path], progress: { line in
                self.emit(progress, line)
            })
            guard !self.cancelled else { self.finishCancelled(finished); return }
            guard code == 0 else {
                self.finish(finished, .failure(PerfectLoopInstallError(message: "安装未完成（网络或磁盘问题），可重试；已下载部分会缓存")))
                return
            }

            // 5) 清运行时缓存 → 立即生效（插件发现是懒加载的）
            Transcoder.invalidatePerfectLoopRuntime()
            self.emit(progress, "安装完成，已立即启用 ✓")
            self.finish(finished, .success(()))
        }
    }

    func cancel() {
        cancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isInstalling = false
    }

    // MARK: - 内部

    /// 静默安装脚本：与 dist 里的 .command 逻辑一致，但无交互、输出到 stdout 供 UI 显示。
    /// 源码从临时解压目录取（tmp），装到用户目录（HOME 由进程环境继承）。
    private func writeSilentScript(to url: URL, tmp: URL) -> Bool {
        let script = """
        #!/bin/bash
        set -euo pipefail
        SRC="\(tmp.path)"
        say() { printf '%s\\n' "$1"; }
        fail() { printf '\\n[失败] %s\\n' "$1" >&2; exit 1; }

        HOME_DIR="$HOME"
        PLUGIN_DIR="$HOME_DIR/.local/share/VideoWallpaper/perfectloop-plugin"
        VENV_DIR="$HOME_DIR/.local/share/VideoWallpaper/perfectloop-venv"
        UV_BIN="$HOME_DIR/.local/bin/uv"
        PYTHON_REQUIRED=3.11
        export PATH="$HOME_DIR/.local/bin:$PATH"

        # 1/4 uv
        if [ -x "$UV_BIN" ]; then
          say "[1/4] Python 环境管理器已就绪"
        else
          say "[1/4] 正在安装 Python 环境管理器…"
          if command -v curl >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || fail "环境管理器安装失败，请检查网络"
          elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || fail "环境管理器安装失败，请检查网络"
          else
            fail "系统缺少 curl/wget，无法自动安装"
          fi
          [ -x "$UV_BIN" ] || fail "环境管理器未装到预期位置，请重试"
        fi

        # 2/4 venv + 依赖
        say "[2/4] 正在准备 Python 环境并下载依赖（约 330 MB）…"
        mkdir -p "$(dirname "$VENV_DIR")"
        if [ ! -x "$VENV_DIR/bin/python3" ]; then
          "$UV_BIN" venv --python "$PYTHON_REQUIRED" "$VENV_DIR" >/dev/null 2>&1 || \\
            "$UV_BIN" venv --python python3 "$VENV_DIR" >/dev/null 2>&1 || \\
            fail "Python 环境创建失败，请检查网络"
        fi
        PYTHON="$VENV_DIR/bin/python3"
        export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
        install_pkg() {
          local pkg="$1" i
          for i in 1 2 3; do
            if "$UV_BIN" pip install --python "$PYTHON" "$pkg" >/dev/null 2>&1; then return 0; fi
            say "      $pkg 下载第 $i 次未成功，重试…"
            sleep 2
          done
          return 1
        }
        for pkg in numpy pillow networkx imageio scipy opencv-python-headless scikit-image; do
          install_pkg "$pkg" || fail "$pkg 下载失败，请检查网络后重试"
        done
        say "      依赖安装完成"

        # 3/4 部署源码
        say "[3/4] 正在部署插件…"
        mkdir -p "$PLUGIN_DIR"
        cp -R "$SRC/PerfectLoop" "$PLUGIN_DIR/"
        cp "$SRC/perfectloop_runner.py" "$PLUGIN_DIR/"
        find "$PLUGIN_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
        find "$PLUGIN_DIR" -name '*.pyc' -delete 2>/dev/null || true
        chmod +x "$PLUGIN_DIR/perfectloop_runner.py"

        # 4/4 自检
        say "[4/4] 自检中…"
        CHECK="$("$PYTHON" "$PLUGIN_DIR/perfectloop_runner.py" --check 2>&1)" || fail "自检未通过：$CHECK"
        case "$CHECK" in *OK*) ;; *) fail "自检未通过：$CHECK" ;; esac
        say "安装完成"
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// 简单执行（不取输出），返回退出码。
    private func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// 执行并把 stdout/stderr 逐行回调（用于显示进度）。
    private func runStreaming(_ exe: String, _ args: [String], progress: @escaping (String) -> Void) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        currentProcess = p
        guard (try? p.run()) != nil else { currentProcess = nil; return -1 }

        let handle = pipe.fileHandleForReading
        var buffer = ""
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { return }
            buffer += String(data: data, encoding: .utf8) ?? ""
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[buffer.startIndex..<nl])
                buffer.removeSubrange(buffer.startIndex...nl)
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { progress(trimmed) }
            }
        }
        p.waitUntilExit()
        handle.readabilityHandler = nil
        if !buffer.isEmpty {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { progress(trimmed) }
        }
        currentProcess = nil
        return p.terminationStatus
    }

    /// 同步下载（放在后台队列调用）。
    private func download(_ urlString: String, to dest: URL) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.downloadTask(with: url) { temp, response, error in
            defer { sem.signal() }
            guard error == nil, let temp,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            ok = (try? FileManager.default.moveItem(at: temp, to: dest)) != nil
        }
        task.resume()
        sem.wait()
        return ok
    }

    private func emit(_ progress: @escaping (String) -> Void, _ line: String) {
        DispatchQueue.main.async { progress(line) }
    }

    private func finish(_ finished: @escaping (Result<Void, PerfectLoopInstallError>) -> Void, _ result: Result<Void, PerfectLoopInstallError>) {
        isInstalling = false
        DispatchQueue.main.async { finished(result) }
    }

    private func finishCancelled(_ finished: @escaping (Result<Void, PerfectLoopInstallError>) -> Void) {
        finish(finished, .failure(PerfectLoopInstallError(message: "已取消")))
    }
}
