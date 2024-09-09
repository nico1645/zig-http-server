const std = @import("std");
const TailQueue = std.TailQueue;

pub fn BlockingQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Node: type = TailQueue(T).Node;

        mutex: std.Thread.Mutex = std.Thread.Mutex{},
        list: TailQueue(T) = TailQueue(T){},

        pub fn enqueue(self: *Self, node: *TailQueue(T).Node) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.list.prepend(node);
        }

        pub fn dequeue(self: *Self) ?*TailQueue(T).Node {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.list.pop();
        }
    };
}

test "blocking queue" {
    const Queue = BlockingQueue(u8);
    var queue = Queue{};
    var t1 = Queue.Node{ .data = 10 };
    var t2 = Queue.Node{ .data = 5 };
    queue.enqueue(&t1);
    queue.enqueue(&t2);
    const ten = queue.dequeue().?.data;
    const five = queue.dequeue().?.data;
    try std.testing.expect(ten == 10);
    try std.testing.expect(five == 5);
    try std.testing.expect(queue.dequeue() == null);
}
