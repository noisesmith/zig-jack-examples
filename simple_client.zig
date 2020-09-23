const std = @import("std");
const print = std.debug.print;
const exit = std.process.exit;
const destroy = std.heap.c_allocator.destroy;
const sleep = std.time.sleep;

const c = @cImport({
    @cInclude("jack/jack.h");
});

var input: ?*c.jack_port_t = undefined;
var output: ?*c.jack_port_t = undefined;

pub fn main() u8 {
    var ports: *?[*:0]const u8 = undefined;
    var client_name: [*:0]const u8 = "simple";
    var server_name: ?[*:0]const u8 = null;
    var status: c.jack_status_t = undefined;

    const client = c.jack_client_open(client_name, .JackNullOption, &status, server_name) orelse {
        print("jack_client_open() failed, status = {}\n", .{@enumToInt(status)});
        if ((@enumToInt(status) & c.JackServerFailed) != 0) {
            print("failed to connect to JACK server\n", .{});
        }
        exit(2);
    };
    defer _ = c.jack_client_close(client);

    if ((@enumToInt(status) & c.JackServerStarted) != 0) {
        print("new jack server started\n", .{});
    }
    if ((@enumToInt(status) & c.JackNameNotUnique) != 0) {
        client_name = c.jack_get_client_name(client);
        print("unique name '{}' assigned\n", .{client_name});
    }

    _ = c.jack_set_process_callback(client, process_audio, null);
    c.jack_on_shutdown(client, jack_shutdown, null);
    print("engine sample rate: {}\n", .{c.jack_get_sample_rate(client)});

    input = c.jack_port_register(client, "input", c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsInput, 0);
    output = c.jack_port_register(client, "output", c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsOutput, 0);

    if ((input == null) or (output == null)) {
        print("no more Jack ports available\n", .{});
        exit(1);
    }
    if (c.jack_activate(client) != 0) {
        print("cannot activate client\n", .{});
        exit(1);
    }

    const hardware_output = c.JackPortIsPhysical | c.JackPortIsOutput;
    ports = c.jack_get_ports(client, null, null, hardware_output) orelse {
        print("no physical capture ports available\n", .{});
        exit(1);
    };
    // if we were doing more than just using the first port returned, it would be something like:
    // for (std.mem.span(ports)) |port| { // do something }
    if (c.jack_connect(client, ports.*, c.jack_port_name(input)) != 0) {
        print("cannot connect input ports\n", .{});
    }
    destroy(ports);
    const hardware_input = c.JackPortIsPhysical | c.JackPortIsInput;
    ports = c.jack_get_ports(client, null, null, hardware_input) orelse {
        print("no physical playback ports available\n", .{});
        exit(1);
    };
    if (c.jack_connect(client, c.jack_port_name(output), ports.*) != 0) {
        print("connot connect output ports", .{});
    }
    destroy(ports);
    sleep(std.math.maxInt(u64));
    return 0;
}

fn process_audio(nframes: c.jack_nframes_t, user_data: ?*c_void) callconv(.C) c_int {
    var in = @ptrCast([*]u8, c.jack_port_get_buffer(input, nframes));
    var out = @ptrCast([*]u8, c.jack_port_get_buffer(output, nframes));

    // just copy input to output
    @memcpy(out, in, @sizeOf(c.jack_default_audio_sample_t) * nframes);
    return 0;
}

fn jack_shutdown(arg: ?*c_void) callconv(.C) void {
    exit(1);
}
