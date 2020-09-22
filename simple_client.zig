const std = @import("std");
const print = std.debug.print;
const exit = std.process.exit;

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("jack/jack.h");
});

var input: ?*c.jack_port_t = undefined;
var output: ?*c.jack_port_t = undefined;
var client: ?*c.jack_client_t = undefined;

const c_null = @as(c_int, 0);
const null_ptr = @intToPtr(?*c_void, c_null);
const null_ports = @intToPtr(?*align(8) u8, c_null);
const long_null = @as(c_long, c_null);
const null_client = @ptrCast(?*c.jack_client_t, null_ptr);
const data_desc = "32 bit float mono audio";
const null_port = @ptrCast(?*c.jack_port_t, null_ptr);
const client_options = @intToEnum(c.jack_options_t, c.JackNullOption);
const sample_size = @sizeOf(c.jack_default_audio_sample_t);

pub fn main() u8 {
    var ports: *[*:0]const u8 = undefined;
    var client_name: [*:0]const u8 = "simple";
    var server_name: ?*const u8 = null;
    var status: c.jack_status_t = undefined;
    var status_code: i32 = undefined;
    var ports_raw: [*c][*c]const u8 = undefined;

    client = c.jack_client_open(client_name, client_options,
        &status, server_name);
    status_code = @enumToInt(status);

    if (client == null_client) {
        print("jack_client_open() failed, status = {}\n", .{status_code});
        if ((status_code & c.JackServerFailed) != 0) {
            print("failed to connect to JACK server\n", .{});
        }
        exit(2);
    }
    if ((status_code & c.JackServerStarted) != 0) {
        print("new jack server started\n", .{});
    }
    if ((status_code & c.JackNameNotUnique) != 0) {
        client_name = c.jack_get_client_name(client);
        print("unique name '{}' assigned\n", .{client_name});
    }

    _ = c.jack_set_process_callback(client, process_audio, null);
    c.jack_on_shutdown(client, jack_shutdown, null);
    print("engine sample rate: {}\n", .{c.jack_get_sample_rate(client)});

    input = c.jack_port_register(client, "input", data_desc,
        c.JackPortIsInput, long_null);
    output = c.jack_port_register(client, "output", data_desc,
        c.JackPortIsOutput, long_null);

    if ((input == null_port) or (output == null_port)) {
        print("no more Jack ports available\n", .{});
        exit(1);
    }
    if (c.jack_activate(client) != 0) {
        print("cannot activate client\n", .{});
        exit(1);
    }

    const hardware_output = c.JackPortIsPhysical | c.JackPortIsOutput;
    ports_raw = c.jack_get_ports(client, null, null, hardware_output);
    ports = @ptrCast(*[*:0]const u8, ports_raw);
    if (@ptrCast(?* u8, ports) == null_ports) {
        print("no physical capture ports available\n", .{});
        exit(1);
    }
    if (c.jack_connect(client, ports.*, c.jack_port_name(input)) != 0) {
        print("cannot connect input ports\n", .{});
    }
    const hardware_input = c.JackPortIsPhysical | c.JackPortIsInput;
    ports_raw = c.jack_get_ports(client, null, null, hardware_input);
    ports = @ptrCast(*[*:0]const u8, ports_raw);
    if (@ptrCast(?* u8, ports) == null_ports) {
        print("no physical playback ports available\n", .{});
        exit(1);
    }
    if (c.jack_connect(client, c.jack_port_name(output), ports.*) != 0) {
        print("connot connect output ports", .{});
    }
    c.free(@ptrCast(*c_void, ports));
    // in C this was -1, which zig is smart enough to reject for unsigned
    _ = c.sleep(0xFFFFFFFF);
    _ = c.jack_client_close(client);
    return 0;
}

export fn shut_down(arg: *c_void) void {
    exit(1);
}

export fn process_audio(nframes: c.jack_nframes_t, user_data: ?*c_void) c_int {
    var in = c.jack_port_get_buffer(input, nframes);
    var out = c.jack_port_get_buffer(output, nframes);

    const copy_size = sample_size * nframes;

    // just copy input to output
    _ = c.memcpy(out, in, copy_size);
    return 0;
}

pub export fn jack_shutdown(arg: ?*c_void) void {
    exit(1);
}
