# Privacy / 隐私说明

Pasteback stores text, images, timestamps and source-app identifiers only in the current Mac user’s `~/Library/Application Support/Pasteback/` directory. Runtime history is not part of the GitHub repository or the install package. There are no accounts, ads, analytics or cloud-history sync.

The local history directory uses owner-only permissions; new history files also use owner-only permissions. These are access controls, not encryption. Software running as the same user or an administrator may read the data. Sensitive pasteboard flags and excluded apps are skipped, but unmarked passwords can still be captured. Pause recording before handling sensitive content.

## Optional update request

Only when the user clicks **Check for Updates**, the app requests the latest public stable release from:

`https://api.github.com/repos/JohnSmitho91p8/Pasteback/releases/latest`

It uses an ephemeral HTTP session, does not send clipboard contents or source-app history, and does not use analytics or tracking identifiers. Normal connection metadata (including IP address) and the app version in the User-Agent are visible to GitHub. Opening the release download page uses the user’s browser and GitHub’s privacy policy applies.

There is no automatic background polling for updates and no automatic installation.

## Delete and clear

A preview’s Delete button removes that history item; it does not change the system clipboard. The panel’s Clear menu can clear only the current system clipboard, or clear both all history (including pinned items) and the clipboard. The Settings clear-history control affects history only. Deletion is logical application deletion, not a guarantee of secure SSD erasure or removal from user-managed backups.

## 中文摘要

历史只存本机，不上传、不云同步；源码、安装包不包含用户历史。当前文件有账户权限限制，但尚未应用层加密，不能承诺设备被攻破后仍绝对保密。

新增“检查更新”会在用户点击时访问 GitHub，只获取公开版本信息，不发送剪贴板内容。GitHub 会接收正常网络连接信息及 App 版本。下载与安装由用户手动完成。
