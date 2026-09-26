# App Store 描述更新文案

用途：提交合规版本（建议版本号 1.07）时更新 App Store 元数据。
所有 `[REPO URL]` 在 GitHub 仓库公开后替换为实际地址。

---

## 1. 英文描述（Description）——在现有描述末尾追加

```
OPEN SOURCE & LICENSES

Real imPro contains a Swift port of substantial portions of Impro-Visor ("Improvisation Advisor") by Prof. Robert Keller and Harvey Mudd College, used under the GNU General Public License v2. The complete corresponding source code is published at:

[REPO URL]

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v2 for details.

Real imPro also uses VexFlow (MIT License) and follows an approach from music21 (BSD 3-Clause License); full texts and attributions are available in the in-app "Licenses" screen (Settings → Acknowledgments & Licenses).
```

## 2. 中文描述——在现有描述末尾追加

```
开源与许可

Real imPro 包含对 Impro-Visor（"Improvisation Advisor"，作者 Robert Keller 教授与 Harvey Mudd College）大量代码的 Swift 移植，基于 GNU 通用公共许可证 v2（GPL v2）使用。完整对应源代码已公开发布于：

[REPO URL]

本程序按"现状"分发，不提供任何明示或默示的担保（包括适销性与特定用途适用性）。详见 GPL v2。

本应用同时使用 VexFlow（MIT 许可），并参考了 music21（BSD 3-Clause 许可）的实现思路；完整许可证文本与署名见 App 内「设置 → 致谢与开源许可」页面。
```

## 3. What's New（本版本更新说明）

英文：

```
- Added an "Acknowledgments & Licenses" screen (Settings), with full attribution to the open-source projects used by Real imPro and a link to the complete source code.
- Minor fixes and stability improvements.
```

中文：

```
- 在「设置」中新增「致谢与开源许可」页，完整署名本应用使用的开源项目，并提供完整源代码链接。
- 若干问题修复与稳定性改进。
```

## 4. App Store Connect 字段建议

- **License（许可证）字段**：不要继续使用标准苹果 EULA 的"无特殊许可"状态而不加说明。做法二选一：
  1. 保持 Standard EULA，并在描述中加入上述 GPL 声明（多数 GPL iOS 应用的实际做法）；
  2. 在 License 字段填入自定义 EULA 文本，其中写明"本软件包含 GPL v2 代码，源代码见 [REPO URL]，GPL 赋予用户的源代码获取与再分发权利不受 EULA 限制"。
  → 建议先用做法 1，配合 App 内许可页与仓库；若 Keller 对苹果条款有异议，再按做法 2 或调整。
- **Support URL（支持网址）**：可直接用公开仓库地址（GitHub 仓库页面可作为支持页）。
- **销售区域**：若暂不处理欧盟个别曲目（Beyond the Blue Horizon，Harling 卒于 1958，EU 保护期至 2028 年），可暂时取消欧盟区域销售，或在下一版本移除该曲；美国区域无版权问题。

## 5. 提审注意

- 提审包内必须包含已接入的「致谢与开源许可」页（入口位置确认后接入）。
- 仓库在提审前转为公开（或至少审核人员可访问）；仓库 tag 与提审版本号对应（v1.07）。
- 不要在描述中删除付费/内购相关表述；GPL 允许收费，无需回避。
