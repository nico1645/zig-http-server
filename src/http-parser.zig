const std = @import("std");

const HTTPParseError = error{
    InvalidHTTPMethod,
    InvalidRequestLine,
    InvalidHeader,
    InvalidRequest,
    ResponseBodyTooLarge,
};

pub const HTTPMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    HEAD,
    TRACE,
    CONNECT,

    pub fn init(string: []const u8) HTTPParseError!HTTPMethod {
        if (string.len < 3) {
            return HTTPParseError.InvalidHTTPMethod;
        }
        return switch (string[0]) {
            'G' => HTTPMethod.GET,
            'P' => {
                return switch (string[1]) {
                    'O' => HTTPMethod.POST,
                    'U' => HTTPMethod.PUT,
                    'A' => HTTPMethod.PATCH,
                    else => HTTPParseError.InvalidHTTPMethod,
                };
            },
            'D' => HTTPMethod.DELETE,
            'O' => HTTPMethod.OPTIONS,
            'H' => HTTPMethod.HEAD,
            'T' => HTTPMethod.TRACE,
            'C' => HTTPMethod.CONNECT,
            else => HTTPParseError.InvalidHTTPMethod,
        };
    }
};

pub const HTTPRequest = struct {
    method: HTTPMethod,
    path: []const u8,
    version: []const u8,
    headers: std.ArrayList([]const u8),
    data: ?[]u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator) HTTPRequest {
        return HTTPRequest{
            .method = undefined,
            .version = undefined,
            .path = undefined,
            .headers = std.ArrayList([]const u8).init(allocator.*),
            .data = null,
            .allocator = allocator.*,
        };
    }

    pub fn deinit(httpRequest: *const HTTPRequest) void {
        httpRequest.headers.deinit();
        if (httpRequest.data) |data| {
            httpRequest.allocator.free(data);
        }
    }
};

fn parseRequestLine(allocator: *const std.mem.Allocator, line: []const u8) HTTPParseError!HTTPRequest {
    var iter = std.mem.splitSequence(u8, line, " ");

    const method: []const u8 = iter.next() orelse return HTTPParseError.InvalidRequestLine;
    const path = iter.next() orelse return HTTPParseError.InvalidRequestLine;
    const version = iter.next() orelse return HTTPParseError.InvalidRequestLine;

    const parsed_method = try HTTPMethod.init(method);

    var http_request = HTTPRequest.init(allocator);
    http_request.method = parsed_method;
    http_request.path = path;
    http_request.version = version;

    return http_request;
}

fn parseHeader(line: []const u8) HTTPParseError![]const u8 {
    if (std.mem.indexOf(u8, line, ":") == null) {
        return HTTPParseError.InvalidHeader;
    }
    return line;
}

pub fn parseHTTPRequest(allocator: *const std.mem.Allocator, request: []const u8) !HTTPRequest {
    var reader = std.mem.splitSequence(u8, request, "\r\n");
    const request_line = reader.next() orelse return HTTPParseError.InvalidRequest;

    var http_request = try parseRequestLine(allocator, request_line);

    while (reader.next()) |line| {
        if (line.len == 0) {
            break;
        }
        const header = try parseHeader(line);
        try http_request.headers.append(header);
    }
    const data = reader.rest();
    if (data.len == 0) {
        return http_request;
    }
    http_request.data = try allocator.alloc(u8, data.len);
    std.mem.copyForwards(u8, http_request.data.?, data);

    return http_request;
}
