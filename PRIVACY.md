# Privacy / 隐私说明

Pasteback stores text, images, timestamps and source-app identifiers only in the current Mac user’s `~/Library/Application Support/Pasteback/` directory. Runtime history is not part of the GitHub repository or the install package. There are no accounts, ads, analytics or cloud-history sync.

The local history directory uses owner-only permissions; new history files also use owner-only permissions. These are access controls, not encryption. Software running as the same user or an administrator may read the data. Sensitive pasteboard flags and excluded apps are skipped, but unmarked passwords can still be captured. Pause recording before handling sensitive content.

## File references and automatic pasting

From 0.3.0, file history stores references: local paths, names, directory flags, sizes, content types and modification dates. It does not copy file contents. Paths may contain usernames or project names. Removing file history never deletes the original files. At most 200 file references are recorded per clipboard item. File promises are not supported; moved files are not tracked with bookmarks.

Optional automatic pasting is off by default. Enabling it requires macOS Accessibility permission, used to send Command-V to the app that was active before opening Pasteback. The app checks permission, secure input and target focus and otherwise falls back to copying; this is best-effort protection, not a guarantee that every application accepts a paste. Pasteback does not request Accessibility access for its normal copy-only behavior.

## History migration backups

Before the first 0.3.0 schema migration of an existing history database, Pasteback creates an owner-restricted local database backup in its data directory. Failed migration restores the pre-migration database rather than creating empty history. Backups may contain old text and file metadata. Ordinary history deletion does not erase migration backups; they can be reviewed and removed separately using the local data folder. Images remain stored separately. Backups are not uploaded and are not application-level encrypted.

## Optional update request

Starting with 0.2.0, clicking **Check for Updates** uses Sparkle to request the public signed feed:

`https://raw.githubusercontent.com/JohnSmitho91p8/Pasteback/main/appcast.xml`

If the user chooses to install, Sparkle downloads the archive from this repository’s GitHub Releases, verifies its EdDSA signature, replaces the app and relaunches it. Clipboard history is never included in these requests and is not replaced by the installer. No system profiling or analytics is enabled. GitHub receives ordinary connection metadata such as IP address and User-Agent. Checks and installation are user initiated; no background polling or silent installation is enabled.

## Delete and clear

A preview’s Delete button removes that history item; it does not change the system clipboard. The panel’s Clear menu can clear only the current system clipboard, or clear both all history (including pinned items) and the clipboard. The Settings clear-history control affects history only. Deletion is logical application deletion, not a guarantee of secure SSD erasure or removal from user-managed backups.

## 中文摘要

历史只存本机，不上传、不云同步；源码、安装包不包含用户历史。当前文件有账户权限限制，但尚未应用层加密，不能承诺设备被攻破后仍绝对保密。

点击“检查更新”会访问 GitHub 获取签名版本列表；用户选择安装后，由 App 下载、验证签名、安装并重启。不发送剪贴板内容，不启用系统画像和统计。GitHub 会接收正常网络连接信息。无后台检查或静默安装。

0.3.0 文件记录仅保存路径、名称和元数据，不复制文件内容；路径可能包含用户名和项目名。删除文件历史不会删除原文件。自动粘贴默认关闭，需用户主动授权辅助功能；遇到权限、安全输入或焦点问题时尽力退回只复制，不保证所有应用都接受粘贴。首次迁移旧库前在本地自动备份；普通清空不会同时擦除迁移备份，备份需在本地数据目录单独管理。
