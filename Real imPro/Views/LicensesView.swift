//
//  LicensesView.swift
//  Real imPro
//
//  合规新增文件：App 内「致谢与开源许可」页。
//  本文件为新增文件，不改动任何既有代码；入口位置待确认后接入。
//

import SwiftUI

struct LicensesView: View {

    // 仓库公开后替换为实际 URL（与 README、App Store 文案保持一致）
    private let sourceRepositoryURL = URL(string: "https://github.com/onlyonear/RealimPro")!
    private let contactURL = URL(string: "mailto:onearonly@gmail.com")!

    var body: some View {
        Form {
            // MARK: Impro-Visor / GPL
            Section(header: Text(NSLocalizedString("致谢", comment: ""))) {
                Text(verbatim: "Real imPro contains a Swift port of substantial portions of Impro-Visor (\"Improvisation Advisor\"), created by Prof. Robert Keller and Harvey Mudd College.")
                Text(verbatim: "Impro-Visor — https://www.cs.hmc.edu/~keller/jazz/improvisor/")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(verbatim: "Copyright (C) 2005-2017 Robert Keller and Harvey Mudd College")
                    .font(.footnote)
            }

            Section(header: Text(NSLocalizedString("GNU 通用公共许可证 v2", comment: ""))) {
                Text(verbatim: "Impro-Visor is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version. This derivative work is released under version 2 of the License.")
                Text(verbatim: "This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.")
                Link(destination: sourceRepositoryURL) {
                    Label(NSLocalizedString("查看完整源代码（GitHub）", comment: ""), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text(verbatim: "If you cannot access the repository, you may request a machine-readable copy of the source corresponding to your version by email: onearonly@gmail.com")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // MARK: VexFlow / MIT
            Section(header: Text(NSLocalizedString("VexFlow — MIT License", comment: ""))) {
                Text(verbatim: "Copyright (c) Mohit Muthanna Cheppudira and VexFlow contributors")
                    .font(.footnote)
                Text(verbatim: Self.mitLicenseText)
                    .font(.footnote)
            }

            // MARK: music21 / BSD-3
            Section(header: Text(NSLocalizedString("music21 — BSD 3-Clause License", comment: ""))) {
                Text(verbatim: "The MusicXML repeat-expansion behavior was independently implemented following the approach used by music21. No music21 source code is included.")
                    .font(.footnote)
                Text(verbatim: "Copyright (c) Michael Scott Cuthbert and the music21 Project")
                    .font(.footnote)
                Text(verbatim: Self.bsdLicenseText)
                    .font(.footnote)
            }

            // MARK: SoundFont
            Section(header: Text(NSLocalizedString("音源 SoundFont", comment: ""))) {
                Text(verbatim: "The bundled SoundFont is a custom revision of Chorium by openwrld (openwrld@kebi.com), derived from the Chorium/ChoriumRevA SoundFont, used with attribution.")
                    .font(.footnote)
            }

            // MARK: Contact
            Section(header: Text(NSLocalizedString("联系方式", comment: ""))) {
                Link(destination: contactURL) {
                    Label("onearonly@gmail.com", systemImage: "envelope")
                }
            }
        }
        .navigationTitle(NSLocalizedString("致谢与开源许可", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: License texts

    static let mitLicenseText = """
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

    static let bsdLicenseText = """
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""
}
