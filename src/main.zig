const std = @import("std");
const net = std.net;
const print = std.debug.print;
const parser = @import("http-parser.zig");
const bqueue = @import("blocking-queue.zig");

pub fn printArray(array: *const std.ArrayList([]const u8)) void {
    print("{{ ", .{});
    defer print("}}\n", .{});
    for (array.items) |item| {
        print("{s}, ", .{item});
    }
}

pub fn acceptRequest(allocator: std.mem.Allocator, queue: *bqueue.BlockingQueue(net.Stream), dir: *[]const u8) !void {
    main_loop: while (true) {
        const max_request_size = 125000;
        const node = queue.dequeue() orelse continue;
        defer allocator.destroy(node);
        const stream = node.data;
        defer stream.close();

        var buf: [max_request_size]u8 = undefined;
        const end = try stream.read(&buf);

        if (end == max_request_size) {
            _ = try stream.write("HTTP/1.1 413 Content Too Large\r\n\r\n");
            continue;
        }

        const httpRequest: parser.HTTPRequest = try parser.parseHTTPRequest(&allocator, buf[0..end]);
        defer httpRequest.deinit();

        if (httpRequest.path.len == 1) {
            if (httpRequest.method != parser.HTTPMethod.GET) {
                _ = try stream.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
                continue;
            }
            _ = try stream.write("HTTP/1.1 200 OK\r\n\r\n");
            continue;
        }

        var path_it = std.mem.splitSequence(u8, httpRequest.path[1..], "/");

        if (path_it.next()) |word| {
            if (std.mem.eql(u8, word, "echo")) {
                if (httpRequest.method != parser.HTTPMethod.GET) {
                    _ = try stream.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
                    continue;
                }
                if (path_it.next()) |text| {
                    if (path_it.peek() == null) {
                        for (httpRequest.headers.items) |item| {
                            var tmp = std.mem.splitSequence(u8, item, ": ");
                            const header_name = tmp.next() orelse continue;
                            const header_val = tmp.next() orelse continue;

                            if (std.ascii.eqlIgnoreCase(header_name, "accept-encoding")) {
                                if (std.mem.containsAtLeast(u8, header_val, 1, "gzip")) {
                                    var in: [256]u8 = undefined;
                                    var inStream = std.io.fixedBufferStream(&in);
                                    var out: [256]u8 = undefined;
                                    var outStream = std.io.fixedBufferStream(&out);
                                    _ = try inStream.write(text);
                                    //_ = try std.compress.gzip.compress(inStream.reader(), outStream.writer(), std.compress.gzip.Options{});
                                    const written: []u8 = outStream.getWritten();
                                    const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ written.len, written });
                                    defer allocator.free(res);
                                    _ = try stream.write(res);
                                    continue :main_loop;
                                }
                            }
                        }
                        const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ text.len, text });
                        defer allocator.free(res);
                        _ = try stream.write(res);
                        continue;
                    }
                }
            } else if (std.mem.eql(u8, word, "user-agent") and path_it.peek() == null) {
                if (httpRequest.method != parser.HTTPMethod.GET) {
                    _ = try stream.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
                }
                for (httpRequest.headers.items) |item| {
                    var tmp = std.mem.splitSequence(u8, item, ": ");
                    const header_name = tmp.next() orelse continue;
                    const header_val = tmp.next() orelse continue;

                    if (std.ascii.eqlIgnoreCase(header_name, "user-agent")) {
                        const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ header_val.len, header_val });
                        defer allocator.free(res);
                        _ = try stream.write(res);
                    }
                }
                continue;
            } else if (std.mem.eql(u8, word, "files") and path_it.peek() != null) {
                const filename = path_it.next().?;
                const path = try std.fs.path.join(allocator, &[_][]const u8{ dir.*, filename });
                defer allocator.free(path);
                if (filename.len == 0 or path_it.peek() != null) {
                    print("Invalid path specified: {s}\n", .{path});
                    _ = try stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
                    continue;
                }

                switch (httpRequest.method) {
                    parser.HTTPMethod.GET => {
                        const fs = std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{}) catch {
                            print("Invalid path specified: {s}\n", .{path});
                            _ = try stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
                            continue :main_loop;
                        };
                        defer fs.close();

                        const file_bytes = fs.readToEndAlloc(allocator, 100000) catch {
                            _ = try stream.write("HTTP/1.1 413 Content Too Large\r\n\r\n");
                            continue :main_loop;
                        };
                        const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text\r\nContent-Length: {d}\r\n\r\n{s}", .{ file_bytes.len, file_bytes });
                        defer allocator.free(res);
                        _ = try stream.write(res);
                    },
                    parser.HTTPMethod.POST => {
                        const fs = try std.fs.createFileAbsolute(path, std.fs.File.CreateFlags{});
                        defer fs.close();
                        if (httpRequest.data) |data| {
                            _ = try fs.writeAll(data);
                        }
                        _ = try stream.write("HTTP/1.1 201 Created\r\n\r\n");
                    },
                    else => {
                        _ = try stream.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
                    },
                }
                continue;
            }
        }
        print("Invalid path specified: {s}\n", .{httpRequest.path});
        _ = try stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var dir_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    var directory: []u8 = undefined;

    var args = std.process.args();
    _ = args.next();
    if (args.next()) |item| {
        if (std.mem.eql(u8, item, "--directory")) {
            if (args.next()) |file| {
                directory = try std.fs.realpath(file, &dir_buf);
            }
        } else if (std.mem.eql(u8, item, "help") or std.mem.eql(u8, item, "--help")) {
            print("Specify the dir path to the files you want to serve.\nArgument --directory (default is the current dir)\n", .{});
            std.process.exit(0);
        } else {
            print("Unexpected CLI argument: {s}\n", .{item});
            std.process.exit(1);
        }
    } else {
        directory = try std.fs.realpath("./", &dir_buf);
    }

    const Queue = bqueue.BlockingQueue(net.Stream);
    var queue = Queue{};

    const loopback = net.Ip4Address.init(.{ 127, 0, 0, 1 }, 4221);
    const address = net.Address{ .in = loopback };
    var server = try address.listen(.{});
    defer server.deinit();

    // Consumer Threads
    for (0..try std.Thread.getCpuCount()) |i| {
        _ = i;
        _ = try std.Thread.spawn(.{}, acceptRequest, .{ allocator, &queue, &directory });
    }

    print("Listening on {}, access this port to end the program\n", .{address.getPort()});

    // Producer Thread
    while (true) {
        const client = try server.accept();
        const node = try allocator.create(Queue.Node);
        node.*.data = client.stream;
        queue.enqueue(node);
    }
}
