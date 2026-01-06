// ============================================================================
// HINGE PACKAGE MANAGER - PHASE B INTEGRATION
// ============================================================================
//
// Doctrine: Sovereign supply chain with capability validation
// - Content-addressed packages with BLAKE3 Merkle trees
// - SBOM generation for supply chain transparency
// - Deterministic tar.zst compression for reproducibility
// - Integration with our high-performance serde framework
//
// Performance: Optimized for large-scale package distribution
// Security: Cryptographically verified package integrity
// Reproducibility: Deterministic builds with content addressing
//

const std = @import("std");
// serde integration via local shim (future: swap to real Janus serde)
// const serde = @import("serde_shim.zig");
const packer = @import("packer.zig");
const crypto = @import("crypto_dilithium.zig");
const ledger_local = @import("ledger_local.zig");
const keyring = @import("keyring.zig");
const tlog = @import("transparency_log.zig");

pub const Command = union(enum) {
    pub const Tag = enum {
        pack,
        resolve,
        fetch,
        verify,
        seal,
        publish,
        checkpoint,
        log_sync,
        log_verify,
        checkpoint_verify,
    };

    pack: PackCommand,
    resolve: ResolveCommand,
    fetch: FetchCommand,
    verify: VerifyCommand,
    seal: SealCommand,
    publish: PublishCommand,
    checkpoint: CheckpointCommand,
    log_sync: LogSyncCommand,
    log_verify: LogVerifyCommand,
    checkpoint_verify: CheckpointVerifyCommand,
};

pub const PackCommand = struct {
    source_path: []const u8,
    package_name: []const u8,
    version: []const u8,
    config: packer.PackerConfig = .{},
};

pub const ResolveCommand = struct {
    manifest_path: []const u8,
    lockfile_path: []const u8 = "JANUS.lock",
};

pub const FetchCommand = struct {
    package_name: []const u8,
    version: ?[]const u8 = null,
    registry: []const u8 = "https://registry.janus-lang.org",
};

pub const VerifyCommand = struct {
    package_path: []const u8,
    signature_path: ?[]const u8 = null,
};

pub const SealCommand = struct {
    package_path: []const u8,
    private_key_path: []const u8,
    output_path: []const u8,
};

pub const PublishCommand = struct {
    package_path: []const u8,
    registry: []const u8 = "https://registry.janus-lang.org",
    public_key_path: []const u8,
};

pub const CheckpointCommand = struct {
    from: ?[]const u8 = null,
};

pub const LogSyncCommand = struct {
    registry: []const u8 = "https://registry.janus-lang.org",
    since: ?[]const u8 = null,
};

pub const LogVerifyCommand = struct {
    log_entry: []const u8,
    registry: []const u8 = "https://registry.janus-lang.org",
};

pub const CheckpointVerifyCommand = struct {
    checkpoint_path: []const u8,
    trust_pub_path: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp();
        return;
    }

    const command_name = args[1];

    // Parse command flags
    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    var positional_args: std.ArrayList([]const u8) = .empty;
    defer positional_args.deinit(allocator);

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            const flag_name = arg[2..];
            if (i + 1 < args.len) {
                try flags.put(flag_name, args[i + 1]);
                i += 1;
            } else {
                try flags.put(flag_name, "");
            }
        } else {
            try positional_args.append(allocator, arg);
        }
    }

    // Dispatch to appropriate command handler
    if (std.mem.eql(u8, command_name, "pack")) {
        try handlePackCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "resolve")) {
        try handleResolveCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "fetch")) {
        try handleFetchCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "verify")) {
        try handleVerifyCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "seal")) {
        try handleSealCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "publish")) {
        try handlePublishCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "checkpoint")) {
        try handleCheckpointCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "log-sync")) {
        try handleLogSyncCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "log-verify")) {
        try handleLogVerifyCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "checkpoint-verify")) {
        try handleCheckpointVerifyCommand(allocator, &positional_args, &flags);
    } else if (std.mem.eql(u8, command_name, "trust")) {
        try handleTrustCommand(allocator, &positional_args, &flags);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command_name});
        try printHelp();
    }
}

fn handlePackCommand(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 3) {
        std.debug.print("Usage: hinge pack <source> <name> <version> [--format FORMAT] [--output DIR] [--sbom] [--sign]\n", .{});
        return error.InvalidArgument;
    }

    const source_path = args.items[0];
    const package_name = args.items[1];
    const version = args.items[2];

    // Parse configuration from flags
    var config = packer.PackerConfig{};

    if (flags.get("format")) |format_str| {
        if (std.mem.eql(u8, format_str, "jpk")) {
            config.package_format = .jpk;
        } else if (std.mem.eql(u8, format_str, "tar.zst")) {
            config.package_format = .tar_zst;
        } else if (std.mem.eql(u8, format_str, "zip")) {
            config.package_format = .zip;
        }
    }

    if (flags.get("output")) |output| {
        config.output_dir = output;
    }

    if (flags.get("sbom")) |_| {
        config.include_sbom = true;
    }

    if (flags.get("sign")) |_| {
        config.sign_package = true;
        if (flags.get("key")) |key| {
            config.signature_key = key;
        }
    }

    // Create packer and pack the package
    var package_packer = try packer.PackagePacker.init(allocator, config, "cas/");
    defer package_packer.deinit();

    var package = try package_packer.pack(source_path, package_name, version);
    defer package.deinit();

    // Write package to output
    const output_path = try std.fmt.allocPrint(allocator, "{s}{s}-{s}.jpk", .{ config.output_dir, package_name, version });
    defer allocator.free(output_path);

    try package_packer.writePackage(&package, output_path);

    std.debug.print("🎉 Package {s}@{s} successfully packed!\n", .{ package_name, version });
    const hash_hex = try packer.hexSlice(allocator, &package.hash_b3.?);
    defer allocator.free(hash_hex);
    std.debug.print("   BLAKE3 hash: {s}\n", .{hash_hex});
    std.debug.print("   Output: {s}\n", .{output_path});

    // Ledger entry (pack)
    if (package.hash_b3) |h| {
        const hex = try packer.hexSlice(allocator, &h);
        defer allocator.free(hex);
        try ledger_local.append("pack", package_name, version, output_path, hex, null, null, allocator);
    }
}

fn handleResolveCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), _: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 1) {
        std.debug.print("Usage: hinge resolve <manifest.jan> [--lockfile LOCKFILE]\n", .{});
        return error.InvalidArgument;
    }

    const manifest_path = args.items[0];
    // const lockfile_path = flags.get("lockfile") orelse "JANUS.lock";

    std.debug.print("🔍 Resolving dependencies for {s}\n", .{manifest_path});

    // TODO: Implement dependency resolution using our serde framework
    // This should use janus.json for high-performance parsing
    // TODO: implement dependency resolution

    std.debug.print("⚠️  Dependency resolution not yet implemented\n", .{});
}

fn handleFetchCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 1) {
        std.debug.print("Usage: hinge fetch <package> [version] [--registry REGISTRY]\n", .{});
        return error.InvalidArgument;
    }

    const package_name = args.items[0];
    const version = args.items[1];
    const registry = flags.get("registry") orelse "https://registry.janus-lang.org";

    std.debug.print("📥 Fetching {s}@{s} from {s}\n", .{ package_name, version, registry });

    // TODO: Implement package fetching with HTTP client and capability validation
    // TODO: implement package fetching

    std.debug.print("⚠️  Package fetching not yet implemented\n", .{});
}

fn handleVerifyCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 1) {
        std.debug.print("Usage: hinge verify <package> [--signature SIGNATURE]\n", .{});
        return error.InvalidArgument;
    }

    const package_path = args.items[0];
    // const signature_path = flags.get("signature");

    std.debug.print("🔐 Verifying package {s}\n", .{package_path});

    // Allocator for verification work
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read BLAKE3 hash (package/package/hash.b3)
    const hash_path = try std.fs.path.join(allocator, &.{ package_path, "package", "hash.b3" });
    defer allocator.free(hash_path);
    const hash_hex = try std.fs.cwd().readFileAlloc(allocator, hash_path, 1024);
    defer allocator.free(hash_hex);

    var hash_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&hash_bytes, std.mem.trim(u8, hash_hex, " \n\r\t"));

    // Determine trust mode and threshold
    const mode_str = flags.get("mode") orelse "consensus"; // "strict" or "consensus"
    const threshold_str = flags.get("threshold") orelse "1/1";
    const th = crypto.parseThreshold(threshold_str) orelse return error.InvalidArgument;

    // Gather signatures: prefer package/package/signatures/*.sig + matching *.pub
    const sigs_dir = try std.fs.path.join(allocator, &.{ package_path, "package", "signatures" });
    defer allocator.free(sigs_dir);
    var total_pairs: usize = 0;
    var valid_count: usize = 0;
    var trusted_valid_count: usize = 0;
    const dir_opt: ?std.fs.Dir = std.fs.cwd().openDir(sigs_dir, .{ .iterate = true }) catch null;
    if (dir_opt) |dir_val| {
        var dir = dir_val;
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".sig")) continue;
            const base = entry.name[0 .. entry.name.len - 4];
            const sig_path = try std.fs.path.join(allocator, &.{ sigs_dir, entry.name });
            defer allocator.free(sig_path);
            const pub_name = try std.fmt.allocPrint(allocator, "{s}.pub", .{base});
            defer allocator.free(pub_name);
            const pub_path = try std.fs.path.join(allocator, &.{ sigs_dir, pub_name });
            defer allocator.free(pub_path);

            const sig = std.fs.cwd().readFileAlloc(allocator, sig_path, 4096) catch continue;
            defer allocator.free(sig);
            const pub_key = std.fs.cwd().readFileAlloc(allocator, pub_path, 4096) catch continue;
            defer allocator.free(pub_key);
            total_pairs += 1;
            if (crypto.verify(pub_key, &hash_bytes, std.mem.trim(u8, sig, " \n\r\t"))) {
                valid_count += 1;
                if (try keyring.isTrusted(allocator, pub_key)) trusted_valid_count += 1;
            }
        }
    } else {
        const sig_path = try std.fs.path.join(allocator, &.{ package_path, "package", "signature.d3" });
        defer allocator.free(sig_path);
        const pk_path = try std.fs.path.join(allocator, &.{ package_path, "package", "public.key" });
        defer allocator.free(pk_path);
        const signature = try std.fs.cwd().readFileAlloc(allocator, sig_path, 4096);
        defer allocator.free(signature);
        const public_key = try std.fs.cwd().readFileAlloc(allocator, pk_path, 4096);
        defer allocator.free(public_key);
        total_pairs = 1;
        if (crypto.verify(public_key, &hash_bytes, std.mem.trim(u8, signature, " \n\r\t"))) {
            valid_count = 1;
            if (try keyring.isTrusted(allocator, public_key)) trusted_valid_count = 1;
        }
    }

    if (std.mem.eql(u8, mode_str, "strict")) {
        if (total_pairs == 0 or trusted_valid_count < 1) return error.AccessDenied;
    } else {
        // consensus: N-of-M
        if (total_pairs == 0) return error.AccessDenied;
        if (trusted_valid_count < th.n) return error.AccessDenied;
    }
    std.debug.print("✅ Signatures valid: {d}/{d}, trusted: {d} (mode={s}, threshold={s})\n", .{ valid_count, total_pairs, trusted_valid_count, mode_str, threshold_str });

    // Ledger entry (verify)
    const hash_hex_ok = try packer.hexSlice(allocator, &hash_bytes);
    defer allocator.free(hash_hex_ok);
    try ledger_local.append("verify", package_path, "-", package_path, hash_hex_ok, @intCast(valid_count), @intCast(total_pairs), allocator);

    // Optional export of Merkle proof against checkpoint
    if (flags.get("export-proof")) |proof_path| {
        // Find statement line containing this hash in the local tlog
        const local_path = try tlog.TL.defaultPath(allocator);
        defer allocator.free(local_path);
        const f = std.fs.cwd().openFile(local_path, .{}) catch null;
        if (f == null) return error.FileNotFound;
        defer f.?.close();
        const content = try f.?.readToEndAlloc(allocator, 64 * 1024 * 1024);
        defer allocator.free(content);
        const needle_key = "\"hash\":\"";
        const hash_str = try packer.hexSlice(allocator, &hash_bytes);
        defer allocator.free(hash_str);
        var it = std.mem.splitScalar(u8, content, '\n');
        var stmt_line: ?[]u8 = null;
        while (it.next()) |line| {
            if (line.len == 0) continue;
            if (std.mem.indexOf(u8, line, needle_key)) |p| {
                const start = p + needle_key.len;
                if (std.mem.startsWith(u8, line[start..], hash_str)) {
                    stmt_line = try allocator.dupe(u8, line);
                    break;
                }
            }
        }
        const statement = stmt_line orelse return error.FileNotFound;
        defer allocator.free(statement);
        var log = tlog.TL.init(allocator, local_path);
        const proof = (try log.proofForStatement(statement)) orelse return error.FileNotFound;
        defer allocator.free(@constCast(proof.siblings));
        const recomputed = tlog.TL.verifyProof(statement, proof);

        // Read checkpoint
        const cpath = try defaultCheckpointPath(allocator);
        defer allocator.free(cpath);
        const cfile = std.fs.cwd().openFile(cpath, .{}) catch return error.FileNotFound;
        defer cfile.close();
        const cjson = try cfile.readToEndAlloc(allocator, 4096);
        defer allocator.free(cjson);
        const croot = parseCheckpointRootHex(cjson) orelse return error.InvalidArgument;
        const ok_ledger = std.mem.eql(u8, &recomputed, &croot);

        // Write proof JSON file (manual printer)
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        var w = out.writer(allocator);
        try w.print("{{\"index\":{},\"total\":{},\"siblings\":[", .{ proof.index, proof.total });
        var i: usize = 0;
        while (i < proof.siblings.len) : (i += 1) {
            if (i > 0) try w.writeByte(',');
            try w.writeByte('"');
            const sib_hex = try packer.hexSlice(allocator, &proof.siblings[i]);
            defer allocator.free(sib_hex);
            try w.print("{s}", .{sib_hex});
            try w.writeByte('"');
        }
        const recomputed_hex = try packer.hexSlice(allocator, &recomputed);
        defer allocator.free(recomputed_hex);
        const croot_hex = try packer.hexSlice(allocator, &croot);
        defer allocator.free(croot_hex);
        try w.print(
            "],\"root\":\"{s}\",\"checkpoint_root\":\"{s}\",\"verified\":{s}}}\n",
            .{ recomputed_hex, croot_hex, if (ok_ledger) "true" else "false" },
        );
        try std.fs.cwd().writeFile(.{ .sub_path = proof_path, .data = out.items });
        std.debug.print("🧾 Proof exported to {s} (ok={s})\n", .{ proof_path, if (ok_ledger) "true" else "false" });
    }
}

fn handleSealCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 3) {
        std.debug.print("Usage: hinge seal <package> <private_key> <output>\n", .{});
        return error.InvalidArgument;
    }

    const package_path = args.items[0];
    const private_key_path = args.items[1];
    const output_path = args.items[2];

    std.debug.print("🔏 Sealing package {s}\n", .{package_path});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read private key
    const private_key = try std.fs.cwd().readFileAlloc(allocator, private_key_path, 4096);
    defer allocator.free(private_key);

    // Read BLAKE3 hash (package/package/hash.b3)
    const hash_path = try std.fs.path.join(allocator, &.{ package_path, "package", "hash.b3" });
    defer allocator.free(hash_path);
    const hash_hex = try std.fs.cwd().readFileAlloc(allocator, hash_path, 1024);
    defer allocator.free(hash_hex);

    var hash_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&hash_bytes, std.mem.trim(u8, hash_hex, " \n\r\t"));

    // Sign and emit artifacts
    const sig = try crypto.sign(std.mem.trim(u8, private_key, " \n\r\t"), &hash_bytes, allocator);
    defer allocator.free(sig);
    const pub_key = try crypto.derivePublicKey(allocator, std.mem.trim(u8, private_key, " \n\r\t"));
    defer allocator.free(pub_key);

    if (flags.get("into-package")) |_| {
        // Write into package/package/signatures/<keyid>.*
        const sigs_dir = try std.fs.path.join(allocator, &.{ package_path, "package", "signatures" });
        defer allocator.free(sigs_dir);
        try std.fs.cwd().makePath(sigs_dir);
        // Key id = blake3(pub_key) hex prefix
        var h = std.crypto.hash.Blake3.init(.{});
        h.update(pub_key);
        var hbytes: [32]u8 = undefined;
        h.final(&hbytes);
        const hex_key = try packer.hexSlice(allocator, &hbytes);
        defer allocator.free(hex_key);
        const keyid = hex_key[0..16];
        const sig_name = try std.fmt.allocPrint(allocator, "{s}.sig", .{keyid});
        defer allocator.free(sig_name);
        const pub_name = try std.fmt.allocPrint(allocator, "{s}.pub", .{keyid});
        defer allocator.free(pub_name);
        const sig_out = try std.fs.path.join(allocator, &.{ sigs_dir, sig_name });
        defer allocator.free(sig_out);
        try std.fs.cwd().writeFile(.{ .sub_path = sig_out, .data = sig });
        const pk_out = try std.fs.path.join(allocator, &.{ sigs_dir, pub_name });
        defer allocator.free(pk_out);
        try std.fs.cwd().writeFile(.{ .sub_path = pk_out, .data = pub_key });
        std.debug.print("✅ Package sealed into package signatures dir (keyid={s})\n", .{keyid});
    } else {
        try std.fs.cwd().makePath(output_path);
        const sig_out = try std.fs.path.join(allocator, &.{ output_path, "signature.d3" });
        defer allocator.free(sig_out);
        try std.fs.cwd().writeFile(.{ .sub_path = sig_out, .data = sig });
        const pk_out = try std.fs.path.join(allocator, &.{ output_path, "public.key" });
        defer allocator.free(pk_out);
        try std.fs.cwd().writeFile(.{ .sub_path = pk_out, .data = pub_key });
        std.debug.print("✅ Package sealed (Dilithium3-test). Output: {s}\n", .{output_path});
    }

    // Ledger entry (seal)
    const hash_hex2 = try packer.hexSlice(allocator, &hash_bytes);
    defer allocator.free(hash_hex2);
    try ledger_local.append("seal", package_path, "-", output_path, hash_hex2, null, null, allocator);
}

fn handlePublishCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 2) {
        std.debug.print("Usage: hinge publish <package> <public_key> [--registry REGISTRY]\n", .{});
        return error.InvalidArgument;
    }

    const package_path = args.items[0];
    // const public_key_path = args.items[1];
    const registry = flags.get("registry") orelse "https://registry.janus-lang.org";

    std.debug.print("📤 Publishing package {s} to {s}\n", .{ package_path, registry });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const hash_path = try std.fs.path.join(allocator, &.{ package_path, "package", "hash.b3" });
    defer allocator.free(hash_path);
    const hash_hex = try std.fs.cwd().readFileAlloc(allocator, hash_path, 1024);
    defer allocator.free(hash_hex);
    const hash_trim = std.mem.trim(u8, hash_hex, " \n\r\t");

    // Compute keyid from supplied public key
    const pub_path = args.items[1];
    const pub_bytes = try std.fs.cwd().readFileAlloc(allocator, pub_path, 1 << 20);
    defer allocator.free(pub_bytes);
    var hh = std.crypto.hash.Blake3.init(.{});
    hh.update(pub_bytes);
    var hpub: [32]u8 = undefined;
    hh.final(&hpub);
    const hpub_hex = try packer.hexSlice(allocator, &hpub);
    defer allocator.free(hpub_hex);
    const keyid = hpub_hex[0..16];

    // Build JSON statement
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("hash", .{ .string = hash_trim });
    try obj.put("keyid", .{ .string = keyid });
    try obj.put("ts", .{ .integer = @intCast(std.time.timestamp()) });
    var line = std.io.Writer.Allocating.init(allocator);
    defer line.deinit();
    const rootv = std.json.Value{ .object = obj };
    try std.json.Stringify.value(rootv, .{ .whitespace = .minified }, &line.writer);

    const local_path = try tlog.TL.defaultPath(allocator);
    defer allocator.free(local_path);
    var log = tlog.TL.init(allocator, local_path);
    try log.append(line.written());
    const root = try log.computeRoot();
    const root_hex = try packer.hexSlice(allocator, &root);
    defer allocator.free(root_hex);
    std.debug.print("🌲 Transparency log root after publish: {s}\n", .{root_hex});
}

fn handleLogSyncCommand(_: std.mem.Allocator, _: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    const registry = flags.get("registry") orelse "https://registry.janus-lang.org";
    // const since = flags.get("since");

    std.debug.print("🔄 Syncing transparency log from {s}\n", .{registry});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const local_path = try tlog.TL.defaultPath(allocator);
    defer allocator.free(local_path);
    var log = tlog.TL.init(allocator, local_path);
    if (flags.get("from")) |src| {
        const path = if (std.mem.startsWith(u8, src, "file://")) src[7..] else src;
        const f = std.fs.cwd().openFile(path, .{}) catch |e| {
            std.debug.print("⚠️  Could not read from {s}: {s}\n", .{ src, @errorName(e) });
            return;
        };
        defer f.close();
        const content = try f.readToEndAlloc(allocator, 64 * 1024 * 1024);
        defer allocator.free(content);
        var it = std.mem.splitScalar(u8, content, '\n');
        var appended: usize = 0;
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            try log.append(trimmed);
            appended += 1;
        }
        std.debug.print("⬇️  Appended {d} statements from {s}\n", .{ appended, src });
    }
    if (flags.get("url")) |url| {
        if (flags.get("allow-net") == null) {
            std.debug.print("🔒 Network capability not granted (--allow-net required)\n", .{});
        } else {
            var gpa2 = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa2.deinit();
            const a = gpa2.allocator();
            // Fetch via curl for simplicity
            const res = std.process.Child.run(.{ .allocator = a, .argv = &.{ "curl", "-fsSL", url } }) catch null;
            if (res) |child| {
                defer {
                    a.free(child.stdout);
                    a.free(child.stderr);
                }
                if (child.term == .Exited and child.term.Exited == 0) {
                    const body = child.stdout;
                    // Optional pin
                    if (flags.get("pin")) |pin_hex| {
                        var h = std.crypto.hash.Blake3.init(.{});
                        h.update(body);
                        var out: [32]u8 = undefined;
                        h.final(&out);
                        const out_hex = try packer.hexSlice(a, &out);
                        defer a.free(out_hex);
                        const okpin = std.mem.eql(u8, std.mem.trim(u8, out_hex, "\n\r "), pin_hex);
                        if (!okpin) {
                            std.debug.print("❌ Pin mismatch for {s}\n", .{url});
                            return;
                        }
                    }
                    var it2 = std.mem.splitScalar(u8, body, '\n');
                    var appended2: usize = 0;
                    while (it2.next()) |line| {
                        const trimmed = std.mem.trim(u8, line, " \r\t");
                        if (trimmed.len == 0) continue;
                        try log.append(trimmed);
                        appended2 += 1;
                    }
                    std.debug.print("⬇️  Appended {d} statements from {s}\n", .{ appended2, url });
                } else {
                    std.debug.print("⚠️  curl failed for {s}\n", .{url});
                }
            }
        }
    }
    const root = try log.computeRoot();
    const root_hex2 = try packer.hexSlice(allocator, &root);
    defer allocator.free(root_hex2);
    std.debug.print("🌲 Local transparency root: {s}\n", .{root_hex2});
}

fn handleLogVerifyCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 1) {
        std.debug.print("Usage: hinge log-verify <log_entry> [--registry REGISTRY]\n", .{});
        return error.InvalidArgument;
    }

    const log_entry = args.items[0];
    const registry = flags.get("registry") orelse "https://registry.janus-lang.org";

    std.debug.print("✅ Verifying log entry {s} against {s}\n", .{ log_entry, registry });
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const local_path = try tlog.TL.defaultPath(allocator);
    defer allocator.free(local_path);
    var log = tlog.TL.init(allocator, local_path);
    var statement: []u8 = undefined;
    if (std.fs.path.isAbsolute(log_entry) or (std.mem.indexOfScalar(u8, log_entry, '/')) != null) {
        const hash_path = try std.fs.path.join(allocator, &.{ log_entry, "package", "hash.b3" });
        defer allocator.free(hash_path);
        const hash_hex = try std.fs.cwd().readFileAlloc(allocator, hash_path, 1024);
        defer allocator.free(hash_hex);
        statement = try allocator.dupe(u8, std.mem.trim(u8, hash_hex, " \n\r\t"));
    } else {
        statement = try allocator.dupe(u8, log_entry);
    }
    defer allocator.free(statement);
    const proof_opt = try log.proofForStatement(statement) orelse return error.FileNotFound;
    defer allocator.free(@constCast(proof_opt.siblings));
    const recomputed = tlog.TL.verifyProof(statement, proof_opt);
    const current_root = try log.computeRoot();
    const ok = std.mem.eql(u8, &recomputed, &current_root);
    if (flags.get("json")) |_| {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);
        var w = buf.writer(allocator);
        try w.print("{{\"index\":{},\"total\":{},\"siblings\":[", .{ proof_opt.index, proof_opt.total });
        var i: usize = 0;
        while (i < proof_opt.siblings.len) : (i += 1) {
            if (i > 0) try w.writeByte(',');
            try w.writeByte('"');
            const sib_hex2 = try packer.hexSlice(allocator, &proof_opt.siblings[i]);
            defer allocator.free(sib_hex2);
            try w.print("{s}", .{sib_hex2});
            try w.writeByte('"');
        }
        const cur_root_hex = try packer.hexSlice(allocator, &current_root);
        defer allocator.free(cur_root_hex);
        try w.print("],\"root\":\"{s}\",\"verified\":{s}}}\n", .{ cur_root_hex, if (ok) "true" else "false" });
        std.debug.print("{s}", .{buf.items});
    } else {
        const cur_root_hex2 = try packer.hexSlice(allocator, &current_root);
        defer allocator.free(cur_root_hex2);
        std.debug.print("🌲 Included at index {d}/{d}; proof_len={d}; root {s}; verify={s}\n", .{ proof_opt.index, proof_opt.total, proof_opt.siblings.len, cur_root_hex2, if (ok) "OK" else "FAIL" });
    }
}

fn defaultCheckpointPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".hinge", "checkpoint.json" });
}

fn parseCheckpointRootHex(content: []const u8) ?[32]u8 {
    const key = "\"root\":\"";
    if (std.mem.indexOf(u8, content, key)) |p| {
        const start = p + key.len;
        if (std.mem.indexOfScalarPos(u8, content, start, '"')) |endq| {
            const hex = content[start..endq];
            var out: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&out, hex) catch return null;
            return out;
        }
    }
    return null;
}

fn handleCheckpointCommand(_: std.mem.Allocator, _: *std.ArrayList([]const u8), flags: *std.StringHashMap([]const u8)) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const local_path = try tlog.TL.defaultPath(allocator);
    defer allocator.free(local_path);
    var log = tlog.TL.init(allocator, local_path);
    if (flags.get("from")) |src| {
        const path = if (std.mem.startsWith(u8, src, "file://")) src[7..] else src;
        const f = std.fs.cwd().openFile(path, .{}) catch return;
        defer f.close();
        const content = try f.readToEndAlloc(allocator, 64 * 1024 * 1024);
        defer allocator.free(content);
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            try log.append(trimmed);
        }
    }
    const root = try log.computeRoot();
    const cpath = try defaultCheckpointPath(allocator);
    defer allocator.free(cpath);
    if (std.fs.path.dirname(cpath)) |dirp| try std.fs.cwd().makePath(dirp);
    var f = try std.fs.cwd().createFile(cpath, .{ .truncate = true });
    defer f.close();
    const checkpoint_root_hex = try packer.hexSlice(allocator, &root);
    defer allocator.free(checkpoint_root_hex);
    const checkpoint_json = try std.fmt.allocPrint(allocator, "{{\"root\":\"{s}\",\"ts\":{d}}}\n", .{ checkpoint_root_hex, std.time.timestamp() });
    defer allocator.free(checkpoint_json);
    try f.writeAll(checkpoint_json);
    std.debug.print("📌 Checkpoint written: {s}\n", .{cpath});
}

fn parseJsonStringField(content: []const u8, key_name: []const u8) ?[]const u8 {
    const key = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{key_name}) catch return null;
    defer std.heap.page_allocator.free(key);
    if (std.mem.indexOf(u8, content, key)) |p| {
        const start = p + key.len;
        if (std.mem.indexOfScalarPos(u8, content, start, '"')) |endq| {
            return content[start..endq];
        }
    }
    return null;
}

fn handleCheckpointVerifyCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), _: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 2) {
        std.debug.print("Usage: hinge checkpoint-verify <checkpoint.json> <trust.pub>\n", .{});
        return error.InvalidArgument;
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const cpath = args.items[0];
    const kpath = args.items[1];
    const cfile = try std.fs.cwd().openFile(cpath, .{});
    defer cfile.close();
    const cjson = try cfile.readToEndAlloc(allocator, 4096);
    defer allocator.free(cjson);
    const root_hex = parseJsonStringField(cjson, "root") orelse return error.InvalidArgument;
    const sig_hex = parseJsonStringField(cjson, "sig") orelse return error.InvalidArgument;
    const ts_str = parseJsonStringField(cjson, "ts") orelse return error.InvalidArgument;
    var root_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&root_bytes, root_hex);
    // Build message = root_bytes || ':' || ts
    var msg: std.ArrayList(u8) = .empty;
    defer msg.deinit(allocator);
    try msg.appendSlice(allocator, &root_bytes);
    try msg.append(allocator, ':');
    try msg.appendSlice(allocator, ts_str);
    // Parse signature hex
    const sig_bytes = blk: {
        const tmp = try allocator.alloc(u8, sig_hex.len / 2);
        errdefer allocator.free(tmp);
        _ = try std.fmt.hexToBytes(tmp, sig_hex);
        break :blk tmp;
    };
    defer allocator.free(sig_bytes);
    // Load trust key
    const trust_pub = try std.fs.cwd().readFileAlloc(allocator, kpath, 1 << 20);
    defer allocator.free(trust_pub);
    const ok = crypto.verify(trust_pub, msg.items, sig_bytes);
    std.debug.print("📌 Checkpoint verify: {s}\n", .{if (ok) "OK" else "FAIL"});
}

fn handleTrustCommand(_: std.mem.Allocator, args: *std.ArrayList([]const u8), _: *std.StringHashMap([]const u8)) !void {
    if (args.items.len < 1) {
        std.debug.print("Usage: hinge trust (add <public.key> | list | remove <keyid>)\n", .{});
        return error.InvalidArgument;
    }
    const sub = args.items[0];
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    if (std.mem.eql(u8, sub, "add")) {
        if (args.items.len < 2) {
            std.debug.print("Usage: hinge trust add <public.key>\n", .{});
            return error.InvalidArgument;
        }
        const key_path = args.items[1];
        const keyid = try keyring.addPublicKey(allocator, key_path);
        defer allocator.free(keyid);
        std.debug.print("🔐 Trusted key added: {s}\n", .{keyid});
        return;
    } else if (std.mem.eql(u8, sub, "list")) {
        const ids = try keyring.listKeyIds(allocator);
        defer {
            for (ids) |s| allocator.free(s);
            allocator.free(ids);
        }
        for (ids) |id| std.debug.print("{s}\n", .{id});
        return;
    } else if (std.mem.eql(u8, sub, "remove")) {
        if (args.items.len < 2) {
            std.debug.print("Usage: hinge trust remove <keyid>\n", .{});
            return error.InvalidArgument;
        }
        const keyid = args.items[1];
        try keyring.removeByKeyId(allocator, keyid);
        std.debug.print("🗑️  Removed key: {s}\n", .{keyid});
        return;
    } else {
        std.debug.print("Unknown trust subcommand: {s}\n", .{sub});
        return error.InvalidArgument;
    }
}

fn printHelp() !void {
    std.debug.print(
        \\Janus Package Manager (Hinge) - Phase B
        \\
        \\USAGE:
        \\    hinge <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    pack      Create a .jpk package from source
        \\    resolve   Resolve dependencies and create lockfile
        \\    fetch     Download package from registry
        \\    verify    Verify package integrity and signatures
        \\              --mode strict|consensus   (default: consensus)
        \\              --threshold N/M          (default: 1/1)
        \\              --export-proof <path.json>
        \\    seal      Sign package with cryptographic signature
        \\              --into-package           (write into package/signatures)
        \\    trust     Manage keyring
        \\              add <public.key>         (store key by KeyID)
        \\              list                     (display KeyIDs)
        \\              remove <keyid>           (remove trusted key)
        \\    publish   Publish package to transparency log
        \\    log-sync  Synchronize transparency log
        \\              --from <file://uri|path>   (append statements)
        \\    log-verify Verify log entry inclusion proof
        \\              --json                    (emit proof JSON for CI)
        \\    checkpoint Verify & manage ledger checkpoints
        \\    checkpoint-verify <checkpoint.json> <trust.pub>  # verify signed checkpoint
        \\
        \\EXAMPLES:
        \\    hinge pack ./src mypackage 1.0.0 --sbom --format jpk --sign --key private.key
        \\    hinge resolve manifest.jan --lockfile JANUS.lock
        \\    hinge fetch mypackage 1.0.0 --registry https://registry.example.com
        \\    hinge verify mypackage-1.0.0.jpk --mode consensus --threshold 2/3
        \\    hinge seal mypackage-1.0.0.jpk private.key sealed.jpk --into-package
        \\    hinge publish sealed.jpk public.key
        \\    hinge log-sync --since 2024-01-01T00:00:00Z
        \\    hinge log-verify entry.json
        \\
        \\DOCTRINE:
        \\    Sovereign supply chain with content-addressed packages
        \\    Cryptographic verification and transparency logs
        \\    Deterministic builds with BLAKE3 Merkle trees
        \\    Integration with high-performance serde framework
        \\
    , .{});
}
