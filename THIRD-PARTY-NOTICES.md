# Third party notices

FabDBFEdEnh itself is released under the [MIT License](LICENSE). It uses the following third party components,
which keep their own licenses.

| Component | Version | License | Where |
|---|---|---|---|
| Newtonsoft.Json | 13.0.4 | MIT | `lib\Newtonsoft.Json.dll`, NuGet |
| ICSharpCode.TextEditorEx (built on the SharpDevelop ICSharpCode.TextEditor) | 1.4.0 | LGPL-2.1-or-later | `lib\ICSharpCode.TextEditorEx.dll`, NuGet |
| X# runtime (XSharp.Core, .Data, .Rdd, .RT, .MacroCompiler) | 2.x / 3.x | Apache License 2.0 | not included, referenced from the X# installation |
| xUnit.net (xunit.core, .assert, .abstractions, .execution, VS test adapter) - tests only | 2.9.3 / 2.8.2 | Apache License 2.0 | `FabDBFEdEnh.Tests\lib\`, NuGet |

---

## Newtonsoft.Json

https://www.newtonsoft.com/json - https://github.com/JamesNK/Newtonsoft.Json

The MIT License (MIT)

Copyright (c) 2007 James Newton-King

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## ICSharpCode.TextEditorEx / ICSharpCode.TextEditor

https://github.com/StefH/ICSharpCode.TextEditorEx

Authors: Stef Heyenrath, SharpDevelop, Qwertie and MysticBoy.

Licensed under the GNU Lesser General Public License, version 2.1 or (at your option) any later version
(SPDX: `LGPL-2.1-or-later`). The full license text is available at
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt

FabDBFEdEnh uses this library unmodified and links to it dynamically (a separate DLL). In accordance with the LGPL
you may replace the DLL with your own build of the library: the original source code is available from the project
address above, and the DLL is loaded from the application folder at run time.

---

## X# runtime

https://www.xsharp.eu/ - https://github.com/X-Sharp

Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
The X# runtime assemblies are not part of this repository; they are installed with the X# product and are
referenced by the projects.

---

## xUnit.net

https://xunit.net/ - https://github.com/xunit/xunit

Copyright (c) .NET Foundation and Contributors. Licensed under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0).

Used only by the test project `FabDBFEdEnh.Tests`; it is not part of the FabDBFEdEnh application. The DLLs in
`FabDBFEdEnh.Tests\lib\` are the unmodified NuGet packages, kept for the XIde project (Visual Studio restores them
from NuGet).
