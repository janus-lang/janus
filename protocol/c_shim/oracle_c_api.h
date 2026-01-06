// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Thin C API for Janus Oracle gRPC client/server bridging C++ stubs to Zig.
// This header is C-only to be consumable via Zig @cImport.

#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque client handle
typedef struct JanusOracleClient JanusOracleClient;

// Create a client connection to host:port. Returns NULL on failure.
JanusOracleClient* janus_oracle_client_connect(const char* host, uint16_t port);

// Configure client timeouts (milliseconds). Zero means "no change".
// Applies to connection handshake (WaitForConnected) and per-RPC deadlines.
// Returns 0 on success, non-zero on invalid arguments.
int janus_oracle_client_set_timeouts(JanusOracleClient* client,
                                     uint32_t connect_timeout_ms,
                                     uint32_t rpc_timeout_ms);

// Close and free the client
void janus_oracle_client_disconnect(JanusOracleClient* client);

// Free heap strings returned by this API
void janus_oracle_free_string(const char* s);

// RPC: DocUpdate
// Returns 0 on success, non-zero on failure. On success, *ok_out is set.
int janus_oracle_doc_update(JanusOracleClient* client,
                            const char* uri,
                            const char* content,
                            /*out*/ bool* ok_out);

// RPC: HoverAt
// Returns 0 on success; markdown_out points to a heap string (may be NULL to indicate no hover).
int janus_oracle_hover_at(JanusOracleClient* client,
                          const char* uri,
                          uint32_t line,
                          uint32_t character,
                          /*out*/ const char** markdown_out);

// RPC: DefinitionAt
// Returns 0 on success. *found_out indicates presence; uri_out is heap string when found.
int janus_oracle_definition_at(JanusOracleClient* client,
                               const char* uri,
                               uint32_t line,
                               uint32_t character,
                               /*out*/ bool* found_out,
                               /*out*/ const char** uri_out,
                               /*out*/ uint32_t* def_line_out,
                               /*out*/ uint32_t* def_character_out);

// Simple location struct for references
typedef struct JanusOracleLocation {
    const char* uri;  // heap string owned by caller after copy or must be freed by janus_oracle_free_string
    uint32_t line;
    uint32_t character;
} JanusOracleLocation;

// RPC: ReferencesAt
// Returns 0 on success. locations_out points to an array allocated by the callee; count_out its length.
// Caller must free the array and each location.uri via janus_oracle_free_string.
int janus_oracle_references_at(JanusOracleClient* client,
                               const char* uri,
                               uint32_t line,
                               uint32_t character,
                               bool include_declaration,
                               /*out*/ JanusOracleLocation** locations_out,
                               /*out*/ uint32_t* count_out);

// -------------------- Server API --------------------

typedef struct JanusOracleServer JanusOracleServer;

// Handler function types. All strings are UTF-8, NUL-terminated. Output pointers are ephemeral;
// the server will copy their contents before returning from the call.
typedef int (*JanusDocUpdateFn)(const char* uri,
                                const char* content,
                                /*out*/ bool* ok_out,
                                void* user);

typedef int (*JanusHoverAtFn)(const char* uri,
                              uint32_t line,
                              uint32_t character,
                              /*out*/ const char** markdown_out,
                              void* user);

typedef int (*JanusDefinitionAtFn)(const char* uri,
                                   uint32_t line,
                                   uint32_t character,
                                   /*out*/ bool* found_out,
                                   /*out*/ const char** def_uri_out,
                                   /*out*/ uint32_t* def_line_out,
                                   /*out*/ uint32_t* def_character_out,
                                   void* user);

typedef void (*JanusLocationSinkFn)(void* sink_user,
                                    const char* uri,
                                    uint32_t line,
                                    uint32_t character);

typedef int (*JanusReferencesAtFn)(const char* uri,
                                   uint32_t line,
                                   uint32_t character,
                                   bool include_declaration,
                                   JanusLocationSinkFn sink,
                                   void* sink_user,
                                   void* user);

// Create/destroy server
JanusOracleServer* janus_oracle_server_create(const char* host, uint16_t port);
void janus_oracle_server_destroy(JanusOracleServer* server);

// Set handler callbacks (must be called before start). Returns 0 on success.
int janus_oracle_server_set_handlers(JanusOracleServer* server,
                                     JanusDocUpdateFn on_doc_update,
                                     JanusHoverAtFn on_hover_at,
                                     JanusDefinitionAtFn on_definition_at,
                                     JanusReferencesAtFn on_references_at,
                                     void* user);

// Start/stop the server (non-blocking). Returns 0 on success.
int janus_oracle_server_start(JanusOracleServer* server);
int janus_oracle_server_stop(JanusOracleServer* server);

#ifdef __cplusplus
} // extern "C"
#endif
