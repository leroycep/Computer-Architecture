ace.define(
  "ace/mode/AssemblyLS8",
  [
    "require",
    "exports",
    "ace/lib/oop",
    "ace/mode/text",
    "ace/mode/AssemblyLS8HighlightRules",
  ],
  function (require, exports, module) {
    "use strict";

    var oop = require("ace/lib/oop");
    var TextMode = require("ace/mode/text").Mode;
    var AssemblyLS8HighlightRules = require("ace/mode/AssemblyLS8HighlightRules")
      .AssemblyLS8HighlightRules;

    let Mode = function () {
      this.HighlightRules = AssemblyLS8HighlightRules;
    };

    oop.inherits(Mode, TextMode);

    exports.Mode = Mode;
  }
);

ace.define(
  "ace/mode/AssemblyLS8HighlightRules",
  ["require", "exports", "ace/lib/oop", "ace/mode/text_highlight_rules"],
  function (require, exports, module) {
    "use strict";

    var oop = require("ace/lib/oop");
    var TextHighlightRules = require("ace/mode/text_highlight_rules")
      .TextHighlightRules;

    var AssemblyLS8HighlightRules = function () {
      // regexp must not have capturing parentheses. Use (?:) instead.
      // regexps are ordered -> the first match is used

      this.$rules = {
        start: [
          { token: "string.assembly", regex: /ds\s+[^\n]*/ },
          {
            token: "keyword.control.assembly",
            regex:
              "\\b(?:NOP|HLT|ADD|SUB|DIV|MUL|MOD|AND|NOT|OR|XOR|SHL|SHR|CALL|RET|POP|PUSH|JMP|CMP|JEQ|JNE|JGE|JGT|JLE|JLT|LD|ST|LDI|DEC|INC|INT|IRET|PRA|PRN)\\b",
            caseInsensitive: true,
          },
          {
            token: "variable.parameter.register.assembly",
            regex: "\\b(?:R[0-7])\\b",
            caseInsensitive: true,
          },
          {
            token: "constant.character.decimal.assembly",
            regex: "\\b[0-9]+\\b",
          },
          {
            token: "constant.character.hexadecimal.assembly",
            regex: "\\b0x[A-F0-9]+\\b",
            caseInsensitive: true,
          },
          { token: "entity.name.function.assembly", regex: "^[\\w.]+?:" },
          { token: "comment.assembly", regex: "[;#].*$" },
        ],
      };

      this.normalizeRules();
    };

    AssemblyLS8HighlightRules.metaData = {
      fileTypes: ["asm"],
      name: "Assembly LS8",
      scopeName: "source.assembly",
    };

    oop.inherits(AssemblyLS8HighlightRules, TextHighlightRules);

    exports.AssemblyLS8HighlightRules = AssemblyLS8HighlightRules;
  }
);
