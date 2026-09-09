# image-merger 许可证与第三方通告

## 本项目的许可证

image-merger 自身（Scheme 库与 boot 程序、Python 后端、wrapper、Makefile、
配置示例与文档）采用 **MIT 许可证**，详见根目录 `LICENSE`。

选型理由：与 chez-python（本项目依赖其运行库与构建工具）及本仓库代码风格
保持一致；MIT 为宽松许可，与下列全部捆绑组件的许可证兼容且无传染性义务。

## 分发物（`make dist` 产物）中包含的第三方组件

| 组件 | 许可证 | 说明 | 完整文本 |
|---|---|---|---|
| Chez Scheme（改名的 `image-merger` 二进制、`scheme.boot`、`petite.boot`） | Apache-2.0（部分历史组件 MIT） | Cisco Systems 的 Chez Scheme；分发需要保留版权与许可声明 | `third-party-licenses/chezscheme-APACHE-2.0.txt`、`chezscheme-MIT-notice.txt` |
| chez-python（`chez-python.boot`） | MIT | image-merger 依赖其运行库 | `third-party-licenses/chez-python-MIT.txt` |
| CPython（捆绑 `python/`） | PSF-2.0 等 | python-build-standalone 产物的主体 | `third-party-licenses/CPython-LICENSE.txt`（即捆绑包内 `python/lib/python3.14/LICENSE.txt`） |
| Pillow（预装入捆绑 python） | MIT-CMU（PIL 历史声明） | Python 图像后端 | `third-party-licenses/Pillow-MIT-CMU.txt` |
| python-build-standalone（构建/分发工具链） | MPL-2.0 | 其仓库与构建脚本的许可证；对产物（CPython 等）本身按上表各自许可证适用 | `third-party-licenses/python-build-standalone-MPL-2.0.txt` |

捆绑的 `python/` 目录内还可能包含其自带依赖（如 OpenSSL、zlib、bzip2 等）
的许可声明，随目录一并分发。

## 分发义务提醒

将 `.dist/image-merger/` 打包分发到其他机器时，请随附：

1. 本仓库根目录的 `LICENSE`（本项目 MIT）；
2. 上述 `third-party-licenses/` 全部文本（`make dist` 会自动复制到
   `.dist/image-merger/LICENSES/`）；
3. 捆绑 `python/` 目录自带的许可文件（随目录移动即可）。
