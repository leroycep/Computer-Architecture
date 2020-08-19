ace.config.set('basePath', 'https://pagecdn.io/lib/ace/1.4.12/');

let editor = ace.edit("editor");
editor.setTheme("ace/theme/monokai");
editor.session.setMode("ace/mode/AssemblyLS8");
