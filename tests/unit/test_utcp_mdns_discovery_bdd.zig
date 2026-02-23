// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const posix = std.posix;
const net = std.net;

// mDNS Edge Discovery BDD Test Suite
// These tests follow the Gherkin scenarios in features/transport/utcp-protocol.feature
// Feature: Edge Discovery via mDNS

// Mock mDNS service record for testing
const MockMDnsService = struct {
    name: []const u8,
    service_type: []const u8,
    port: u16,
    txt_records: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, port: u16) MockMDnsService {
        return .{
            .name = name,
            .service_type = "_libertaria._udp.local",
            .port = port,
            .txt_records = .empty,
        };
    }
    
    pub fn deinit(self: *MockMDnsService, allocator: std.mem.Allocator) void {
        for (self.txt_records.items) |record| {
            allocator.free(record);
        }
        self.txt_records.deinit();
    }
    
    pub fn addTxtRecord(self: *MockMDnsService, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        const record = try std.fmt.allocPrint(allocator, "{s}={s}", .{ key, value });
        try self.txt_records.append(record);
    }
};

// Mock peer table for tracking discovered nodes
const PeerTable = struct {
    allocator: std.mem.Allocator,
    peers: std.ArrayList(Peer),
    
    const Peer = struct {
        did: [8]u8,
        address: net.Address,
        discovered_at: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator) PeerTable {
        return .{
            .allocator = allocator,
            .peers = .empty,
        };
    }
    
    pub fn deinit(self: *PeerTable) void {
        self.peers.deinit();
    }
    
    pub fn updatePeer(self: *PeerTable, did: [8]u8, address: net.Address) !void {
        // Check if peer already exists
        for (self.peers.items) |*peer| {
            if (std.mem.eql(u8, &peer.did, &did)) {
                peer.address = address;
                peer.discovered_at = std.time.milliTimestamp();
                return;
            }
        }
        
        // Add new peer
        try self.peers.append(.{
            .did = did,
            .address = address,
            .discovered_at = std.time.milliTimestamp(),
        });
    }
    
    pub fn peerCount(self: *const PeerTable) usize {
        return self.peers.items.len;
    }
    
    pub fn findPeerByDid(self: *const PeerTable, did: [8]u8) ?*const Peer {
        for (self.peers.items) |*peer| {
            if (std.mem.eql(u8, &peer.did, &did)) {
                return peer;
            }
        }
        return null;
    }
};

// Mock mDNS discovery client
const MockMDnsClient = struct {
    allocator: std.mem.Allocator,
    peer_table: *PeerTable,
    listening: bool,
    discovered_services: std.ArrayList(ServiceInfo),
    
    const ServiceInfo = struct {
        name: []const u8,
        host: []const u8,
        port: u16,
        txt_records: std.StringHashMap([]const u8),
    };
    
    pub fn init(allocator: std.mem.Allocator, peer_table: *PeerTable) MockMDnsClient {
        return .{
            .allocator = allocator,
            .peer_table = peer_table,
            .listening = false,
            .discovered_services = .empty,
        };
    }
    
    pub fn deinit(self: *MockMDnsClient) void {
        for (self.discovered_services.items) |*service| {
            self.allocator.free(service.name);
            self.allocator.free(service.host);
            service.txt_records.deinit();
        }
        self.discovered_services.deinit();
    }
    
    pub fn startListening(self: *MockMDnsClient) void {
        self.listening = true;
    }
    
    pub fn stopListening(self: *MockMDnsClient) void {
        self.listening = false;
    }
    
    pub fn simulateServiceAnnouncement(self: *MockMDnsClient, name: []const u8, host: []const u8, port: u16, txt_map: std.StringHashMap([]const u8)) !void {
        if (!self.listening) return;
        
        const service = ServiceInfo{
            .name = try self.allocator.dupe(u8, name),
            .host = try self.allocator.dupe(u8, host),
            .port = port,
            .txt_records = txt_map,
        };
        try self.discovered_services.append(service);
        
        // Extract DID from TXT records if present, otherwise use mock
        var did = [_]u8{0} ** 8;
        if (txt_map.get("did")) |did_str| {
            @memcpy(did[0..@min(did_str.len, 8)], did_str[0..@min(did_str.len, 8)]);
        } else {
            @memcpy(did[0..4], "NODE");
        }
        
        // Parse host address
        const addr = try net.Address.parseIp(host, port);
        try self.peer_table.updatePeer(did, addr);
    }
    
    pub fn createUTCPHelloProbe(self: *MockMDnsClient, service_idx: usize) !?UTCPProbe {
        if (service_idx >= self.discovered_services.items.len) return null;
        
        const service = &self.discovered_services.items[service_idx];
        
        // Extract frame class from TXT records
        var frame_class: FrameClass = .Standard;
        if (service.txt_records.get("frame_class")) |fc_str| {
            if (std.mem.eql(u8, fc_str, "JUMBO")) {
                frame_class = .Jumbo;
            } else if (std.mem.eql(u8, fc_str, "CONSTRAINED")) {
                frame_class = .Constrained;
            } else if (std.mem.eql(u8, fc_str, "MINI")) {
                frame_class = .Mini;
            }
        }
        
        return UTCPProbe{
            .frame_version = 0,
            .frame_type = .Hello,
            .frame_class = frame_class,
            .target_address = service.host,
            .target_port = service.port,
        };
    }
};

const FrameClass = enum {
    Mini,       // 512 bytes
    Constrained, // 1200 bytes
    Standard,   // 1350 bytes
    Jumbo,      // 9000 bytes
};

const UTCPProbe = struct {
    frame_version: u8,
    frame_type: FrameType,
    frame_class: FrameClass,
    target_address: []const u8,
    target_port: u16,
};

const FrameType = enum {
    Hello,
    Ack,
    Nack,
    Data,
};

// Mock mDNS announcer
const MockMDnsAnnouncer = struct {
    allocator: std.mem.Allocator,
    service_name: []const u8,
    port: u16,
    txt_records: std.StringHashMap([]const u8),
    announcing: bool,
    
    pub fn init(allocator: std.mem.Allocator, service_name: []const u8, port: u16) MockMDnsAnnouncer {
        return .{
            .allocator = allocator,
            .service_name = service_name,
            .port = port,
            .txt_records = std.StringHashMap([]const u8).init(allocator),
            .announcing = false,
        };
    }
    
    pub fn deinit(self: *MockMDnsAnnouncer) void {
        var iter = self.txt_records.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.txt_records.deinit();
    }
    
    pub fn addTxtRecord(self: *MockMDnsAnnouncer, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        try self.txt_records.put(key, owned_value);
    }
    
    pub fn startAnnouncing(self: *MockMDnsAnnouncer) void {
        self.announcing = true;
    }
    
    pub fn stopAnnouncing(self: *MockMDnsAnnouncer) void {
        self.announcing = false;
    }
    
    pub fn getServiceType(self: *const MockMDnsAnnouncer) []const u8 {
        return "_libertaria._udp";
    }
};

// ============================================================================
// BDD Scenario 1: Discover local node via mDNS
// ============================================================================

test "Edge Discovery via mDNS: Discover local node via mDNS" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Given I am listening for mDNS announcements
    var peer_table = PeerTable.init(allocator);
    defer peer_table.deinit();
    
    var mdns_client = MockMDnsClient.init(allocator, &peer_table);
    defer mdns_client.deinit();
    
    mdns_client.startListening();
    try std.testing.expect(mdns_client.listening);
    
    // When a node announces "_libertaria._udp" service
    var txt_records = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = txt_records.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        txt_records.deinit();
    }
    
    const frame_class_val = try allocator.dupe(u8, "JUMBO");
    try txt_records.put("frame_class", frame_class_val);
    
    const version_val = try allocator.dupe(u8, "0.1.0");
    try txt_records.put("version", version_val);
    
    const did_val = try allocator.dupe(u8, "node-abc");
    try txt_records.put("did", did_val);
    
    try mdns_client.simulateServiceAnnouncement(
        "node-abc._libertaria._udp.local",
        "192.168.1.100",
        7331,
        txt_records,
    );
    
    // Then I extract the host and port
    try std.testing.expectEqual(@as(usize, 1), mdns_client.discovered_services.items.len);
    try std.testing.expectEqualStrings("192.168.1.100", mdns_client.discovered_services.items[0].host);
    try std.testing.expectEqual(@as(u16, 7331), mdns_client.discovered_services.items[0].port);
    
    // And peer table is updated
    try std.testing.expectEqual(@as(usize, 1), peer_table.peerCount());
    
    // And I create a UTCP HELLO probe
    const probe = try mdns_client.createUTCPHelloProbe(0);
    try std.testing.expect(probe != null);
    try std.testing.expectEqual(@as(u8, 0), probe.?.frame_version);
    try std.testing.expectEqual(FrameType.Hello, probe.?.frame_type);
    try std.testing.expectEqual(FrameClass.Jumbo, probe.?.frame_class);
    try std.testing.expectEqualStrings("192.168.1.100", probe.?.target_address);
    try std.testing.expectEqual(@as(u16, 7331), probe.?.target_port);
    
    // And I send probe to discovered address (simulated)
    // In real implementation, this would call UTCP transport layer
}

// ============================================================================
// BDD Scenario 2: Advertise own mDNS service
// ============================================================================

test "Edge Discovery via mDNS: Advertise own mDNS service" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Given I have a UTCP socket listening on port 7331
    const utcp_port: u16 = 7331;
    
    // When I start mDNS announcer
    var announcer = MockMDnsAnnouncer.init(allocator, "my-node", utcp_port);
    defer announcer.deinit();
    
    // Then I announce "_libertaria._udp" service
    announcer.startAnnouncing();
    try std.testing.expect(announcer.announcing);
    try std.testing.expectEqualStrings("_libertaria._udp", announcer.getServiceType());
    
    // And TXT record includes frame class (JUMBO)
    try announcer.addTxtRecord("frame_class", "JUMBO");
    const frame_class = announcer.txt_records.get("frame_class").?;
    try std.testing.expectEqualStrings("JUMBO", frame_class);
    
    // And TXT record includes node version
    try announcer.addTxtRecord("version", "0.1.0");
    const version = announcer.txt_records.get("version").?;
    try std.testing.expectEqualStrings("0.1.0", version);
    
    // Verify all expected TXT records are present
    try std.testing.expect(announcer.txt_records.contains("frame_class"));
    try std.testing.expect(announcer.txt_records.contains("version"));
}

// ============================================================================
// Additional test: Integration between discovery and peer table
// ============================================================================

test "Edge Discovery via mDNS: Multiple peer discovery" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var peer_table = PeerTable.init(allocator);
    defer peer_table.deinit();
    
    var mdns_client = MockMDnsClient.init(allocator, &peer_table);
    defer mdns_client.deinit();
    
    mdns_client.startListening();
    
    // Simulate multiple nodes announcing
    const nodes = [_]struct {
        name: []const u8,
        host: []const u8,
        port: u16,
        frame_class: []const u8,
    }{
        .{ .name = "node-1", .host = "192.168.1.101", .port = 7331, .frame_class = "JUMBO" },
        .{ .name = "node-2", .host = "192.168.1.102", .port = 7332, .frame_class = "STANDARD" },
        .{ .name = "node-3", .host = "192.168.1.103", .port = 7333, .frame_class = "CONSTRAINED" },
    };
    
    for (nodes) |node| {
        var txt_records = std.StringHashMap([]const u8).init(allocator);
        
        const fc_val = try allocator.dupe(u8, node.frame_class);
        try txt_records.put("frame_class", fc_val);
        
        const ver_val = try allocator.dupe(u8, "0.1.0");
        try txt_records.put("version", ver_val);
        
        const did_val = try allocator.dupe(u8, node.name);
        try txt_records.put("did", did_val);
        
        try mdns_client.simulateServiceAnnouncement(
            try std.fmt.allocPrint(allocator, "{s}._libertaria._udp.local", .{node.name}),
            node.host,
            node.port,
            txt_records,
        );
        
        // Note: txt_records ownership transfers to simulateServiceAnnouncement
    }
    
    // Verify all peers were discovered
    try std.testing.expectEqual(@as(usize, 3), peer_table.peerCount());
    try std.testing.expectEqual(@as(usize, 3), mdns_client.discovered_services.items.len);
    
    // Verify each discovered service has correct frame class
    try std.testing.expectEqualStrings("JUMBO", mdns_client.discovered_services.items[0].txt_records.get("frame_class").?);
    try std.testing.expectEqualStrings("STANDARD", mdns_client.discovered_services.items[1].txt_records.get("frame_class").?);
    try std.testing.expectEqualStrings("CONSTRAINED", mdns_client.discovered_services.items[2].txt_records.get("frame_class").?);
}

test "Edge Discovery via mDNS: Peer table update on re-announcement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var peer_table = PeerTable.init(allocator);
    defer peer_table.deinit();
    
    var mdns_client = MockMDnsClient.init(allocator, &peer_table);
    defer mdns_client.deinit();
    
    mdns_client.startListening();
    
    // First announcement
    var txt_records1 = std.StringHashMap([]const u8).init(allocator);
    const fc1 = try allocator.dupe(u8, "JUMBO");
    try txt_records1.put("frame_class", fc1);
    const ver1 = try allocator.dupe(u8, "0.1.0");
    try txt_records1.put("version", ver1);
    const did1 = try allocator.dupe(u8, "node-xyz");
    try txt_records1.put("did", did1);
    
    try mdns_client.simulateServiceAnnouncement(
        "node-xyz._libertaria._udp.local",
        "192.168.1.100",
        7331,
        txt_records1,
    );
    
    try std.testing.expectEqual(@as(usize, 1), peer_table.peerCount());
    const first_discovered_at = peer_table.peers.items[0].discovered_at;
    
    // Wait a tiny bit (simulate time passing)
    std.time.sleep(10_000); // 10ms
    
    // Re-announcement (same node, possibly different IP)
    var txt_records2 = std.StringHashMap([]const u8).init(allocator);
    const fc2 = try allocator.dupe(u8, "JUMBO");
    try txt_records2.put("frame_class", fc2);
    const ver2 = try allocator.dupe(u8, "0.1.0");
    try txt_records2.put("version", ver2);
    const did2 = try allocator.dupe(u8, "node-xyz");
    try txt_records2.put("did", did2);
    
    try mdns_client.simulateServiceAnnouncement(
        "node-xyz._libertaria._udp.local",
        "192.168.1.101", // Changed IP
        7331,
        txt_records2,
    );
    
    // Peer count should still be 1 (updated, not added)
    try std.testing.expectEqual(@as(usize, 1), peer_table.peerCount());
    
    // But address should be updated
    const updated_addr = peer_table.peers.items[0].address;
    var addr_buf: [64]u8 = undefined;
    const addr_str = try std.fmt.bufPrint(&addr_buf, "{}", .{updated_addr});
    try std.testing.expect(std.mem.containsAtLeast(u8, addr_str, 1, "192.168.1.101"));
}
