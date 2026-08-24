# Third-party notices

## CodeBurn

QuotaBar's optional local session-usage summary follows the local-first usage-analysis direction of [CodeBurn](https://github.com/getagentseal/codeburn). QuotaBar does not bundle or execute the CodeBurn CLI; the Swift scanner in `Sources/QuotaBarCore/LocalUsage.swift` is an independent implementation for Claude and Codex session files.

CodeBurn is Copyright (c) 2026 AgentSeal and is distributed under the MIT License:

```text
MIT License

Copyright (c) 2026 AgentSeal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

QuotaBar does not copy CodeBurn's `src/` or `mac/` source files and does not include its bundled third-party dependencies. If that changes, their notices must be added here before redistribution.
