ace.config.set("basePath", "https://pagecdn.io/lib/ace/1.4.12/");

let editor = ace.edit("editor");
editor.setTheme("ace/theme/monokai");
editor.session.setMode("ace/mode/AssemblyLS8");

const WASM_PATH = "../ls8-web.wasm";

var instance = null;

let utf8_text_encoder = new TextEncoder();
let utf8_text_decoder = new TextDecoder();
let next_buffer_id = 1;
let wasm_owned_buffers = {};
wasm_owned_buffers[0] = new Uint8Array();

const env = {
  get_output_buffer: () => 0,
  buffer_init: () => {
    let buffer_id = next_buffer_id++;
    wasm_owned_buffers[buffer_id] = new Uint8Array(0);
    return buffer_id;
  },
  buffer_extend: (buffer_id, ptr, len) => {
    const wasm_array = new Uint8Array(instance.exports.memory.buffer, ptr, len);
    const prev_array = wasm_owned_buffers[buffer_id];

    wasm_owned_buffers[buffer_id] = new Uint8Array(wasm_array.length + prev_array.length);
    wasm_owned_buffers[buffer_id].set(prev_array, 0);
    wasm_owned_buffers[buffer_id].set(wasm_array, prev_array.length);
  },
  buffer_deinit: (buffer_id) => {
    delete wasm_owned_buffers[buffer_id];
  },
  console_error: (buffer_id) => {
    console.error(utf8_text_decoder.decode(wasm_owned_buffers[buffer_id]));
  },
  console_debug: (buffer_id) => {
    console.debug(utf8_text_decoder.decode(wasm_owned_buffers[buffer_id]));
  },
  console_warn: (buffer_id) => {
    console.warn(utf8_text_decoder.decode(wasm_owned_buffers[buffer_id]));
  },
  console_info: (buffer_id) => {
    console.info(utf8_text_decoder.decode(wasm_owned_buffers[buffer_id]));
  },
  get_time_seconds: () => new Date().getTime(),
};

WebAssembly.instantiateStreaming(fetch(WASM_PATH), { env }).then(
  (obj) => {
    instance = obj.instance;
    instance.exports.init();
  }
);

// A flag that let's us know if the CPU has started execution of the code
let run_interval = null;

const run_stop_button = document.getElementById("run_stop_button");
run_stop_button.addEventListener("click", toggleRunning);

function toggleRunning() {
  if (run_interval) {
    console.log("Stopping execution");
    window.clearInterval(run_interval);
    run_interval = null;
    run_stop_button.textContent = "Run";
  } else {
    instance.exports.reset();
    wasm_owned_buffers[env.get_output_buffer()] = new Uint8Array();

    const asm = utf8_text_encoder.encode(editor.getValue());
    const wasm_array_ptr = instance.exports.malloc(asm.length);
    const wasm_array = new Uint8Array(
      instance.exports.memory.buffer,
      wasm_array_ptr,
      asm.length
    );
    wasm_array.set(asm, 0);

    if (!instance.exports.upload_program(wasm_array_ptr, wasm_array.length)) {
      console.log("Not starting execution");
      return;
    }

    console.log("Starting execution");

    run_interval = window.setInterval(stepMany, 30);
    run_stop_button.textContent = "Stop";
  }
}

const output = document.getElementById("output");

function stepMany() {
  if (!instance.exports.stepMany()) {
    // False was returned, we execution should be stopped
    toggleRunning();
  }
  const text = utf8_text_decoder.decode(wasm_owned_buffers[0]);
  output.textContent = text;
}
