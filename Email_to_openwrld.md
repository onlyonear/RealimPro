# Email to openwrld（SoundFont 再分发许可）

发送账户：onearonly@gmail.com
收件人：openwrld@kebi.com
背景：App 内打包的 ChoriumRevA.sf2 经核验是 openwrld 2023-05-21 的 "Chorium Custom Revision"，
内嵌 ICOP = "all rights reserved to the author(s)"。公开 GPL 仓库（包含再分发权）前需要作者许可。
占位符：https://apps.apple.com/cn/app/real-impro/id6797129785、https://github.com/onlyonear/RealimPro 发送前替换。

---

## 英文正文

**Subject:** Permission to redistribute your Chorium custom revision SoundFont

Hello,

I am developing an iPad app for jazz practice called Real imPro, which uses your custom revision of the Chorium SoundFont (the file is dated 21 May 2023 and credits openwrld@kebi.com). The app is available here:

https://apps.apple.com/cn/app/real-impro/id6797129785

I am in the process of releasing the app's source code under the GNU GPL v2, which requires that recipients be able to redistribute everything included with it. The source repository is:

https://github.com/onlyonear/RealimPro

I would like to ask for your permission to include your SoundFont in the app and in that repository, with clear attribution to you, and to allow recipients to redistribute it as part of the project. If you would prefer that it not be redistributed in source form, I can instead replace it with another SoundFont and keep yours only in the compiled app — please let me know your preference.

Thank you for your work on Chorium.

Best regards,
Shaohua Xu
Developer, Real imPro
onearonly@gmail.com

---

## 处理预案

1. 作者同意再分发 → 保存书面回复，在 NOTICE/README 中改为"redistributed with permission"，仓库可包含 sf2。
2. 作者不回复或不同意 → 替换为许可明确的音源：
   - GeneralUser GS（S. Christian Collins，MIT）
   - MuseScore General（MIT）
   - FluidR3_GM（MIT）
   替换属于资源替换、不改代码逻辑，但音色会变化，需重新试听验证并在更新说明中注明。
3. 时间顺序建议：此邮件与 Keller 邮件同期发出；在两个音源问题落定前，仓库保持私有、App 暂不提交新版本。
