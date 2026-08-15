//! AES-256-CBC encryption/decryption for Elden Ring's regulation.bin.
//!
//! File layout: [16-byte IV][ciphertext]. No padding scheme — the game's
//! regulation payload is always a multiple of the AES block size; on encrypt
//! we zero-pad the tail, which DCX readers ignore (sizes are explicit in the
//! DCX header).
//!
//! The IV the game ships is sixteen zero bytes, and that is what `encrypt`
//! writes unless told otherwise. A random IV would be equally valid for a
//! reader that takes the IV from the file — ours does — but the game is not
//! known to, and there is no reason to differ from the file it accepts:
//! zero IV means the same input produces the same `regulation.bin`, which
//! makes outputs comparable and the writer's behaviour easy to reason about.

const std = @import("std");
const aes = std.crypto.core.aes;

/// Public community-known key, from SoulsFormats (SFUtil.erRegulationKey).
pub const er_regulation_key = [32]u8{
    0x99, 0xBF, 0xFC, 0x36, 0x6A, 0x6B, 0xC8, 0xC6,
    0xF5, 0x82, 0x7D, 0x09, 0x36, 0x02, 0xD6, 0x76,
    0xC4, 0x28, 0x92, 0xA0, 0x1C, 0x20, 0x7F, 0xB0,
    0x24, 0xD3, 0xAF, 0x4E, 0x49, 0x3F, 0xEF, 0x99,
};

pub const block_size = 16;

pub const DecryptError = error{ InputTooShort, InputNotBlockAligned };

/// Decrypts `data` (IV-prefixed AES-256-CBC). Returns freshly allocated plaintext.
pub fn decrypt(allocator: std.mem.Allocator, key: [32]u8, data: []const u8) ![]u8 {
    if (data.len < block_size) return DecryptError.InputTooShort;
    const ciphertext = data[block_size..];
    if (ciphertext.len % block_size != 0) return DecryptError.InputNotBlockAligned;

    const plaintext = try allocator.alloc(u8, ciphertext.len);
    errdefer allocator.free(plaintext);

    const ctx = aes.Aes256.initDec(key);
    var prev: [block_size]u8 = data[0..block_size].*;
    var i: usize = 0;
    while (i < ciphertext.len) : (i += block_size) {
        const cblock: [block_size]u8 = ciphertext[i..][0..block_size].*;
        var pblock: [block_size]u8 = undefined;
        ctx.decrypt(&pblock, &cblock);
        for (&pblock, prev) |*p, v| p.* ^= v;
        @memcpy(plaintext[i..][0..block_size], &pblock);
        prev = cblock;
    }
    return plaintext;
}

/// The IV the game's own `regulation.bin` carries.
pub const game_iv = [_]u8{0} ** block_size;

/// Encrypts `data` with AES-256-CBC, zero-padding to the block size.
/// Returns freshly allocated [IV][ciphertext]. `iv` null uses `game_iv`,
/// the sixteen zero bytes the shipped file has; pass one to differ (tests).
pub fn encrypt(allocator: std.mem.Allocator, key: [32]u8, data: []const u8, iv: ?[block_size]u8) ![]u8 {
    const padded_len = std.mem.alignForward(usize, data.len, block_size);
    const out = try allocator.alloc(u8, block_size + padded_len);
    errdefer allocator.free(out);

    const iv_bytes: [block_size]u8 = iv orelse game_iv;
    @memcpy(out[0..block_size], &iv_bytes);

    const ctx = aes.Aes256.initEnc(key);
    var prev: [block_size]u8 = iv_bytes;
    var i: usize = 0;
    while (i < padded_len) : (i += block_size) {
        var pblock: [block_size]u8 = [_]u8{0} ** block_size;
        const remaining = data.len -| i;
        const n = @min(remaining, block_size);
        @memcpy(pblock[0..n], data[i..][0..n]);
        for (&pblock, prev) |*p, v| p.* ^= v;
        var cblock: [block_size]u8 = undefined;
        ctx.encrypt(&cblock, &pblock);
        @memcpy(out[block_size + i ..][0..block_size], &cblock);
        prev = cblock;
    }
    return out;
}

test "roundtrip" {
    const allocator = std.testing.allocator;
    const msg = "regulation payload test data, deliberately not block aligned.";
    const iv = [_]u8{0xAB} ** block_size;

    const enc = try encrypt(allocator, er_regulation_key, msg, iv);
    defer allocator.free(enc);
    const dec = try decrypt(allocator, er_regulation_key, enc);
    defer allocator.free(dec);

    try std.testing.expect(dec.len >= msg.len);
    try std.testing.expectEqualSlices(u8, msg, dec[0..msg.len]);
    for (dec[msg.len..]) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

test "default IV is the game's: zero, and the output is deterministic" {
    const allocator = std.testing.allocator;
    const msg = "same input, same file";
    const a = try encrypt(allocator, er_regulation_key, msg, null);
    defer allocator.free(a);
    const b = try encrypt(allocator, er_regulation_key, msg, null);
    defer allocator.free(b);
    try std.testing.expectEqualSlices(u8, &game_iv, a[0..block_size]);
    try std.testing.expectEqualSlices(u8, a, b);
}
