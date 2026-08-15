//! Frame images: what a screen capture produces and what the host tools
//! analyse. Pure memory in, memory out — no files, no GPU — so it is
//! host-tested and shared by the injected runtime (encode on the capture
//! thread) and `ermod img` (decode, measure, compare).
//!
//! The on-disk format is PNG (8-bit RGB, zlib deflate through std) so a
//! capture opens anywhere and stays small enough to attach to a finding.
//! `downscale` is a box filter for the request's `scale` (a 4× smaller
//! frame is plenty to see whether an overlay drew and cuts the file 16×).
//! `stats` and `diff` are what a test can assert on without eyes: mean
//! colour and non-black coverage of a region, and how many pixels changed
//! between two frames.

const std = @import("std");
const flate = std.compress.flate;

pub const Image = struct {
    width: u32,
    height: u32,
    /// Tightly packed RGB8, row-major, `width * height * 3` bytes.
    rgb: []u8,

    pub fn deinit(self: *Image, gpa: std.mem.Allocator) void {
        gpa.free(self.rgb);
        self.* = undefined;
    }

    pub fn pixel(self: Image, x: u32, y: u32) [3]u8 {
        const i = (@as(usize, y) * self.width + x) * 3;
        return self.rgb[i..][0..3].*;
    }
};

pub const Rect = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,

    /// `x,y,w,h` — the shape `--rect` takes.
    pub fn parse(text: []const u8) ?Rect {
        var it = std.mem.splitScalar(u8, text, ',');
        var v: [4]u32 = undefined;
        for (&v) |*slot| {
            const part = it.next() orelse return null;
            slot.* = std.fmt.parseInt(u32, std.mem.trim(u8, part, " "), 10) catch return null;
        }
        if (it.next() != null) return null;
        return .{ .x = v[0], .y = v[1], .w = v[2], .h = v[3] };
    }

    fn clamp(self: Rect, img: Image) Rect {
        const x = @min(self.x, img.width);
        const y = @min(self.y, img.height);
        return .{ .x = x, .y = y, .w = @min(self.w, img.width - x), .h = @min(self.h, img.height - y) };
    }
};

// ── source formats ───────────────────────────────────────────────────────

/// How the swapchain stores a pixel; what the capture hands over.
pub const Format = enum(u32) {
    rgba8 = 0,
    bgra8 = 1,
    /// 10 bits per channel, 2 alpha (HDR-capable swapchains).
    rgb10a2 = 2,
    /// Half-float RGBA (scRGB HDR). Tone-mapped by clamp; good enough to see.
    rgba16f = 3,
};

/// Convert `w*h` pixels of `format` (row pitch `pitch` bytes) into a fresh
/// tightly packed RGB8 image.
pub fn fromPixels(gpa: std.mem.Allocator, w: u32, h: u32, format: Format, pitch: usize, src: []const u8) !Image {
    const rgb = try gpa.alloc(u8, @as(usize, w) * h * 3);
    errdefer gpa.free(rgb);
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        const row = src[y * pitch ..];
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const o = (@as(usize, y) * w + x) * 3;
            switch (format) {
                .rgba8 => {
                    const p = row[x * 4 ..][0..4];
                    rgb[o..][0..3].* = .{ p[0], p[1], p[2] };
                },
                .bgra8 => {
                    const p = row[x * 4 ..][0..4];
                    rgb[o..][0..3].* = .{ p[2], p[1], p[0] };
                },
                .rgb10a2 => {
                    const v = std.mem.readInt(u32, row[x * 4 ..][0..4], .little);
                    rgb[o] = @intCast((v & 0x3ff) >> 2);
                    rgb[o + 1] = @intCast(((v >> 10) & 0x3ff) >> 2);
                    rgb[o + 2] = @intCast(((v >> 20) & 0x3ff) >> 2);
                },
                .rgba16f => {
                    const p = row[x * 8 ..][0..8];
                    inline for (0..3) |ch| {
                        const bits = std.mem.readInt(u16, p[ch * 2 ..][0..2], .little);
                        const f: f32 = @floatCast(@as(f16, @bitCast(bits)));
                        rgb[o + ch] = @intFromFloat(std.math.clamp(f, 0.0, 1.0) * 255.0 + 0.5);
                    }
                },
            }
        }
    }
    return .{ .width = w, .height = h, .rgb = rgb };
}

/// Box-filter the image down by an integer factor (1 returns a copy).
/// Trailing rows/columns that do not fill a box are dropped.
pub fn downscale(gpa: std.mem.Allocator, img: Image, factor: u32) !Image {
    const f = @max(factor, 1);
    const w = img.width / f;
    const h = img.height / f;
    const rgb = try gpa.alloc(u8, @as(usize, w) * h * 3);
    errdefer gpa.free(rgb);
    const n: u32 = f * f;
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            var sum: [3]u32 = .{ 0, 0, 0 };
            var dy: u32 = 0;
            while (dy < f) : (dy += 1) {
                var dx: u32 = 0;
                while (dx < f) : (dx += 1) {
                    const p = img.pixel(x * f + dx, y * f + dy);
                    sum[0] += p[0];
                    sum[1] += p[1];
                    sum[2] += p[2];
                }
            }
            const o = (@as(usize, y) * w + x) * 3;
            rgb[o] = @intCast((sum[0] + n / 2) / n);
            rgb[o + 1] = @intCast((sum[1] + n / 2) / n);
            rgb[o + 2] = @intCast((sum[2] + n / 2) / n);
        }
    }
    return .{ .width = w, .height = h, .rgb = rgb };
}

/// Copy out a region (clamped to the image).
pub fn crop(gpa: std.mem.Allocator, img: Image, region: Rect) !Image {
    const r = region.clamp(img);
    const rgb = try gpa.alloc(u8, @as(usize, r.w) * r.h * 3);
    errdefer gpa.free(rgb);
    var y: u32 = 0;
    while (y < r.h) : (y += 1) {
        const src = img.rgb[((@as(usize, r.y) + y) * img.width + r.x) * 3 ..][0 .. @as(usize, r.w) * 3];
        @memcpy(rgb[@as(usize, y) * r.w * 3 ..][0 .. @as(usize, r.w) * 3], src);
    }
    return .{ .width = r.w, .height = r.h, .rgb = rgb };
}

// ── PNG ──────────────────────────────────────────────────────────────────

const png_sig = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

/// Encode as an 8-bit RGB PNG. `level` is a deflate level 1..9 (the
/// runtime uses 1: a frame is 8 MB raw and the encode runs off the render
/// thread but should still finish in well under a second).
pub fn encodePng(gpa: std.mem.Allocator, img: Image, level: u8) ![]u8 {
    // Filter type 0 (none) on every scanline: fast, and the game frame is
    // noisy enough that fancier filters buy little.
    const stride = @as(usize, img.width) * 3;
    const raw = try gpa.alloc(u8, (stride + 1) * img.height);
    defer gpa.free(raw);
    var y: usize = 0;
    while (y < img.height) : (y += 1) {
        raw[y * (stride + 1)] = 0;
        @memcpy(raw[y * (stride + 1) + 1 ..][0..stride], img.rgb[y * stride ..][0..stride]);
    }

    var zout = try std.Io.Writer.Allocating.initCapacity(gpa, raw.len / 4 + 64);
    defer zout.deinit();
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    const opts: flate.Compress.Options = switch (level) {
        0, 1 => .level_1,
        2 => .level_2,
        3 => .level_3,
        4 => .level_4,
        5 => .level_5,
        6 => .level_6,
        7 => .level_7,
        8 => .level_8,
        else => .level_9,
    };
    var comp = try flate.Compress.init(&zout.writer, window, .zlib, opts);
    try comp.writer.writeAll(raw);
    try comp.finish();
    try zout.writer.flush();
    const zdata = zout.written();

    var out = try std.Io.Writer.Allocating.initCapacity(gpa, zdata.len + 128);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(&png_sig);
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], img.width, .big);
    std.mem.writeInt(u32, ihdr[4..8], img.height, .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // colour type: truecolour
    ihdr[10] = 0; // compression
    ihdr[11] = 0; // filter
    ihdr[12] = 0; // interlace
    try chunk(w, "IHDR", &ihdr);
    try chunk(w, "IDAT", zdata);
    try chunk(w, "IEND", "");
    return out.toOwnedSlice();
}

fn chunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(data.len), .big);
    try w.writeAll(&len);
    try w.writeAll(kind);
    try w.writeAll(data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc.final(), .big);
    try w.writeAll(&crc_bytes);
}

pub const DecodeError = error{
    NotPng,
    Unsupported,
    Corrupt,
    OutOfMemory,
};

/// Decode an 8-bit RGB or RGBA, non-interlaced PNG (what `encodePng` and
/// most tools write). Anything else is `Unsupported`.
pub fn decodePng(gpa: std.mem.Allocator, bytes: []const u8) DecodeError!Image {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &png_sig)) return error.NotPng;
    var pos: usize = 8;
    var width: u32 = 0;
    var height: u32 = 0;
    var channels: usize = 0;
    var idat = std.Io.Writer.Allocating.init(gpa);
    defer idat.deinit();
    while (pos + 8 <= bytes.len) {
        const len = std.mem.readInt(u32, bytes[pos..][0..4], .big);
        const kind = bytes[pos + 4 ..][0..4];
        pos += 8;
        if (pos + len + 4 > bytes.len) return error.Corrupt;
        const data = bytes[pos .. pos + len];
        pos += len + 4; // skip crc
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (len != 13) return error.Corrupt;
            width = std.mem.readInt(u32, data[0..4], .big);
            height = std.mem.readInt(u32, data[4..8], .big);
            if (data[8] != 8 or data[12] != 0) return error.Unsupported;
            channels = switch (data[9]) {
                2 => 3,
                6 => 4,
                else => return error.Unsupported,
            };
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            idat.writer.writeAll(data) catch return error.OutOfMemory;
        } else if (std.mem.eql(u8, kind, "IEND")) {
            break;
        }
    }
    if (width == 0 or height == 0 or channels == 0) return error.Corrupt;
    const stride = @as(usize, width) * channels;
    const raw_len = (stride + 1) * height;
    var reader = std.Io.Reader.fixed(idat.written());
    const window = gpa.alloc(u8, flate.max_window_len) catch return error.OutOfMemory;
    defer gpa.free(window);
    var dec = flate.Decompress.init(&reader, .zlib, window);
    const raw = gpa.alloc(u8, raw_len) catch return error.OutOfMemory;
    defer gpa.free(raw);
    dec.reader.readSliceAll(raw) catch return error.Corrupt;

    // Unfilter in place, then pack to RGB.
    const rgb = gpa.alloc(u8, @as(usize, width) * height * 3) catch return error.OutOfMemory;
    errdefer gpa.free(rgb);
    var prev: ?[]u8 = null;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        const line = raw[y * (stride + 1) ..][0 .. stride + 1];
        const filter = line[0];
        const cur = line[1..];
        var i: usize = 0;
        while (i < stride) : (i += 1) {
            const a: u16 = if (i >= channels) cur[i - channels] else 0;
            const b: u16 = if (prev) |p| p[i] else 0;
            const c: u16 = if (prev != null and i >= channels) prev.?[i - channels] else 0;
            const pred: u16 = switch (filter) {
                0 => 0,
                1 => a,
                2 => b,
                3 => (a + b) / 2,
                4 => paeth(a, b, c),
                else => return error.Corrupt,
            };
            cur[i] = @truncate(cur[i] + pred);
        }
        var x: usize = 0;
        while (x < width) : (x += 1) {
            rgb[(y * width + x) * 3 ..][0..3].* = cur[x * channels ..][0..3].*;
        }
        prev = cur;
    }
    return .{ .width = width, .height = height, .rgb = rgb };
}

fn paeth(a: u16, b: u16, c: u16) u16 {
    const p = @as(i32, a) + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// ── measurement ──────────────────────────────────────────────────────────

pub const Stats = struct {
    rect: Rect,
    /// Mean channel values over the region.
    mean: [3]f64,
    /// Fraction of pixels whose max channel is above `dark_threshold`.
    lit_fraction: f64,
    /// Number of distinct colours (quantised to 4 bits per channel) — a
    /// cheap "is anything drawn here" signal.
    distinct: u32,
    brightest: [3]u8,

    pub const dark_threshold = 16;
};

/// Region measurements; `region` null means the whole image.
pub fn stats(img: Image, region: ?Rect) Stats {
    const r = (region orelse Rect{ .x = 0, .y = 0, .w = img.width, .h = img.height }).clamp(img);
    var sum: [3]u64 = .{ 0, 0, 0 };
    var lit: u64 = 0;
    var brightest: [3]u8 = .{ 0, 0, 0 };
    var brightest_v: u32 = 0;
    var seen = std.StaticBitSet(4096).initEmpty();
    var y = r.y;
    while (y < r.y + r.h) : (y += 1) {
        var x = r.x;
        while (x < r.x + r.w) : (x += 1) {
            const p = img.pixel(x, y);
            sum[0] += p[0];
            sum[1] += p[1];
            sum[2] += p[2];
            const mx = @max(p[0], @max(p[1], p[2]));
            if (mx > Stats.dark_threshold) lit += 1;
            const v = @as(u32, p[0]) + p[1] + p[2];
            if (v > brightest_v) {
                brightest_v = v;
                brightest = p;
            }
            seen.set((@as(usize, p[0] >> 4) << 8) | (@as(usize, p[1] >> 4) << 4) | (p[2] >> 4));
        }
    }
    const n: f64 = @floatFromInt(@max(@as(u64, r.w) * r.h, 1));
    return .{
        .rect = r,
        .mean = .{ @as(f64, @floatFromInt(sum[0])) / n, @as(f64, @floatFromInt(sum[1])) / n, @as(f64, @floatFromInt(sum[2])) / n },
        .lit_fraction = @as(f64, @floatFromInt(lit)) / n,
        .distinct = @intCast(seen.count()),
        .brightest = brightest,
    };
}

pub const Diff = struct {
    /// Pixels whose max channel delta exceeds the threshold.
    changed: u64,
    total: u64,
    /// Bounding box of the changed pixels (zero-size when none).
    bbox: Rect,

    pub fn fraction(self: Diff) f64 {
        return @as(f64, @floatFromInt(self.changed)) / @as(f64, @floatFromInt(@max(self.total, 1)));
    }
};

pub const DiffError = error{SizeMismatch};

/// Compare two same-size images; `threshold` is the per-channel delta a
/// pixel must exceed to count (8–16 hides compression and dither noise).
pub fn diff(a: Image, b: Image, threshold: u8) DiffError!Diff {
    if (a.width != b.width or a.height != b.height) return error.SizeMismatch;
    var changed: u64 = 0;
    var min_x: u32 = a.width;
    var min_y: u32 = a.height;
    var max_x: u32 = 0;
    var max_y: u32 = 0;
    var y: u32 = 0;
    while (y < a.height) : (y += 1) {
        var x: u32 = 0;
        while (x < a.width) : (x += 1) {
            const pa = a.pixel(x, y);
            const pb = b.pixel(x, y);
            var d: u8 = 0;
            inline for (0..3) |ch| d = @max(d, if (pa[ch] > pb[ch]) pa[ch] - pb[ch] else pb[ch] - pa[ch]);
            if (d > threshold) {
                changed += 1;
                min_x = @min(min_x, x);
                min_y = @min(min_y, y);
                max_x = @max(max_x, x);
                max_y = @max(max_y, y);
            }
        }
    }
    const bbox: Rect = if (changed == 0)
        .{ .x = 0, .y = 0, .w = 0, .h = 0 }
    else
        .{ .x = min_x, .y = min_y, .w = max_x - min_x + 1, .h = max_y - min_y + 1 };
    return .{ .changed = changed, .total = @as(u64, a.width) * a.height, .bbox = bbox };
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

fn gradient(gpa: std.mem.Allocator, w: u32, h: u32) !Image {
    const rgb = try gpa.alloc(u8, @as(usize, w) * h * 3);
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const o = (@as(usize, y) * w + x) * 3;
            rgb[o] = @truncate(x * 255 / @max(w - 1, 1));
            rgb[o + 1] = @truncate(y * 255 / @max(h - 1, 1));
            rgb[o + 2] = @truncate((x + y) & 0xff);
        }
    }
    return .{ .width = w, .height = h, .rgb = rgb };
}

test "png round-trips an RGB image" {
    var img = try gradient(testing.allocator, 37, 23);
    defer img.deinit(testing.allocator);
    const png = try encodePng(testing.allocator, img, 1);
    defer testing.allocator.free(png);
    try testing.expect(std.mem.eql(u8, png[0..8], &png_sig));
    var back = try decodePng(testing.allocator, png);
    defer back.deinit(testing.allocator);
    try testing.expectEqual(img.width, back.width);
    try testing.expectEqual(img.height, back.height);
    try testing.expectEqualSlices(u8, img.rgb, back.rgb);
}

test "png round-trips at a higher level too and compresses a flat frame" {
    const rgb = try testing.allocator.alloc(u8, 256 * 128 * 3);
    defer testing.allocator.free(rgb);
    @memset(rgb, 40);
    const img = Image{ .width = 256, .height = 128, .rgb = rgb };
    const png = try encodePng(testing.allocator, img, 6);
    defer testing.allocator.free(png);
    try testing.expect(png.len < rgb.len / 50);
    var back = try decodePng(testing.allocator, png);
    defer back.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, rgb, back.rgb);
}

test "decode rejects non-png bytes" {
    try testing.expectError(error.NotPng, decodePng(testing.allocator, "hello"));
}

test "fromPixels converts every source format" {
    // One pixel each: R=255 G=128 B=0.
    const rgba = [_]u8{ 255, 128, 0, 255 };
    var a = try fromPixels(testing.allocator, 1, 1, .rgba8, 4, &rgba);
    defer a.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 255, 128, 0 }, a.rgb);

    const bgra = [_]u8{ 0, 128, 255, 255 };
    var b = try fromPixels(testing.allocator, 1, 1, .bgra8, 4, &bgra);
    defer b.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 255, 128, 0 }, b.rgb);

    var packed_10: [4]u8 = undefined;
    std.mem.writeInt(u32, &packed_10, 1023 | (512 << 10) | (0 << 20) | (3 << 30), .little);
    var c = try fromPixels(testing.allocator, 1, 1, .rgb10a2, 4, &packed_10);
    defer c.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 255, 128, 0 }, c.rgb);

    var half: [8]u8 = undefined;
    std.mem.writeInt(u16, half[0..2], @bitCast(@as(f16, 1.0)), .little);
    std.mem.writeInt(u16, half[2..4], @bitCast(@as(f16, 0.5)), .little);
    std.mem.writeInt(u16, half[4..6], @bitCast(@as(f16, 0.0)), .little);
    std.mem.writeInt(u16, half[6..8], @bitCast(@as(f16, 1.0)), .little);
    var d = try fromPixels(testing.allocator, 1, 1, .rgba16f, 8, &half);
    defer d.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 255, 128, 0 }, d.rgb);
}

test "fromPixels honours the row pitch" {
    // Two rows of one pixel with 8-byte pitch (4 bytes padding).
    const src = [_]u8{ 1, 2, 3, 255, 0, 0, 0, 0, 4, 5, 6, 255, 0, 0, 0, 0 };
    var img = try fromPixels(testing.allocator, 1, 2, .rgba8, 8, &src);
    defer img.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, img.rgb);
}

test "downscale averages boxes and drops the ragged edge" {
    const src = [_]u8{
        0,   0,   0,   255, 255, 255, 9, 9, 9,
        255, 255, 255, 0,   0,   0,   9, 9, 9,
    };
    const img = Image{ .width = 3, .height = 2, .rgb = @constCast(&src) };
    var small = try downscale(testing.allocator, img, 2);
    defer small.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 1), small.width);
    try testing.expectEqual(@as(u32, 1), small.height);
    try testing.expectEqualSlices(u8, &.{ 128, 128, 128 }, small.rgb);
}

test "stats measure a region: dark background, lit patch" {
    const rgb = try testing.allocator.alloc(u8, 10 * 10 * 3);
    defer testing.allocator.free(rgb);
    @memset(rgb, 0);
    // A 2x2 white patch at (5,5).
    for ([_]u32{ 5, 6 }) |y| for ([_]u32{ 5, 6 }) |x| {
        @memset(rgb[(y * 10 + x) * 3 ..][0..3], 255);
    };
    const img = Image{ .width = 10, .height = 10, .rgb = rgb };
    const whole = stats(img, null);
    try testing.expectApproxEqAbs(@as(f64, 0.04), whole.lit_fraction, 1e-9);
    try testing.expectEqual(@as(u32, 2), whole.distinct);
    try testing.expectEqualSlices(u8, &.{ 255, 255, 255 }, &whole.brightest);
    const patch = stats(img, .{ .x = 5, .y = 5, .w = 2, .h = 2 });
    try testing.expectApproxEqAbs(@as(f64, 1.0), patch.lit_fraction, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 255.0), patch.mean[0], 1e-9);
    // Out-of-range rects clamp rather than fault.
    const off = stats(img, .{ .x = 9, .y = 9, .w = 50, .h = 50 });
    try testing.expectEqual(@as(u32, 1), off.rect.w);
}

test "diff counts changed pixels and boxes them" {
    var a = try gradient(testing.allocator, 16, 16);
    defer a.deinit(testing.allocator);
    var b = try gradient(testing.allocator, 16, 16);
    defer b.deinit(testing.allocator);
    const same = try diff(a, b, 8);
    try testing.expectEqual(@as(u64, 0), same.changed);
    try testing.expectEqual(@as(u32, 0), same.bbox.w);
    // Paint a block in b.
    for (3..7) |y| for (10..12) |x| {
        @memset(b.rgb[(y * 16 + x) * 3 ..][0..3], 200);
    };
    const d = try diff(a, b, 8);
    try testing.expect(d.changed >= 6 and d.changed <= 8);
    try testing.expectEqual(@as(u32, 10), d.bbox.x);
    try testing.expectEqual(@as(u32, 3), d.bbox.y);
    try testing.expectEqual(@as(u32, 2), d.bbox.w);
    try testing.expectEqual(@as(u32, 4), d.bbox.h);
    var c = try gradient(testing.allocator, 8, 8);
    defer c.deinit(testing.allocator);
    try testing.expectError(error.SizeMismatch, diff(a, c, 8));
}

test "crop copies the region and clamps" {
    var img = try gradient(testing.allocator, 8, 8);
    defer img.deinit(testing.allocator);
    var c = try crop(testing.allocator, img, .{ .x = 6, .y = 5, .w = 10, .h = 10 });
    defer c.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 2), c.width);
    try testing.expectEqual(@as(u32, 3), c.height);
    try testing.expectEqualSlices(u8, &img.pixel(7, 6), &c.pixel(1, 1));
}

test "Rect.parse" {
    try testing.expectEqual(Rect{ .x = 1, .y = 2, .w = 3, .h = 4 }, Rect.parse("1,2,3,4").?);
    try testing.expect(Rect.parse("1,2,3") == null);
    try testing.expect(Rect.parse("a,2,3,4") == null);
}
