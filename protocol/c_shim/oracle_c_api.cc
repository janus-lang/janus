// C++ implementation of the thin C API bridging to gRPC C++ stubs.
// Compiles in two modes:
//  - With HAVE_JANUS_ORACLE_GRPC_STUBS defined: uses generated stubs and real gRPC.
//  - Without the define: builds fallback stubs that always fail gracefully.

#include "oracle_c_api.h"

#include <stdlib.h>
#include <string.h>

#ifdef HAVE_JANUS_ORACLE_GRPC_STUBS

#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>

#include "oracle.pb.h"
#include "oracle.grpc.pb.h"

struct JanusOracleClient {
    std::shared_ptr<grpc::Channel> channel;
    std::unique_ptr<janus::oracle::Oracle::Stub> stub;
    uint32_t connect_timeout_ms = 1500; // default connect timeout
    uint32_t rpc_timeout_ms = 1000;     // default per-RPC timeout
};

static char* dup_cstr(const std::string& s) {
    if (s.empty()) return nullptr;
    char* out = static_cast<char*>(malloc(s.size() + 1));
    if (!out) return nullptr;
    memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

extern "C" JanusOracleClient* janus_oracle_client_connect(const char* host, uint16_t port) {
    try {
        std::string target = std::string(host ? host : "127.0.0.1") + ":" + std::to_string(port);
        auto channel = grpc::CreateChannel(target, grpc::InsecureChannelCredentials());
        auto stub = janus::oracle::Oracle::NewStub(channel);
        auto* c = new (std::nothrow) JanusOracleClient{ channel, std::move(stub) };
        if (!c) return nullptr;
        // Wait for channel to become ready within default connect timeout
        const auto deadline = std::chrono::system_clock::now() + std::chrono::milliseconds(c->connect_timeout_ms);
        if (!channel->WaitForConnected(deadline)) {
            delete c;
            return nullptr;
        }
        return c;
    } catch (...) {
        return nullptr;
    }
}

extern "C" void janus_oracle_client_disconnect(JanusOracleClient* client) {
    delete client;
}

extern "C" void janus_oracle_free_string(const char* s) {
    free((void*)s);
}

extern "C" int janus_oracle_client_set_timeouts(JanusOracleClient* client,
                                                uint32_t connect_timeout_ms,
                                                uint32_t rpc_timeout_ms) {
    if (!client) return 1;
    if (connect_timeout_ms != 0) client->connect_timeout_ms = connect_timeout_ms;
    if (rpc_timeout_ms != 0) client->rpc_timeout_ms = rpc_timeout_ms;
    return 0;
}

extern "C" int janus_oracle_doc_update(JanusOracleClient* client,
                                        const char* uri,
                                        const char* content,
                                        bool* ok_out) {
    if (!client || !client->stub) return 1;
    try {
        janus::oracle::DocUpdateRequest req;
        req.set_uri(uri ? uri : "");
        req.set_content(content ? content : "");
        janus::oracle::DocUpdateResponse resp;
        grpc::ClientContext ctx;
        // Deadline
        ctx.set_deadline(std::chrono::system_clock::now() + std::chrono::milliseconds(client->rpc_timeout_ms));
        auto status = client->stub->DocUpdate(&ctx, req, &resp);
        if (!status.ok()) {
            if (status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED) return 5;
            return 2;
        }
        if (ok_out) *ok_out = resp.ok();
        return 0;
    } catch (...) {
        return 3;
    }
}

extern "C" int janus_oracle_hover_at(JanusOracleClient* client,
                                      const char* uri,
                                      uint32_t line,
                                      uint32_t character,
                                      const char** markdown_out) {
    if (markdown_out) *markdown_out = nullptr;
    if (!client || !client->stub) return 1;
    try {
        janus::oracle::PositionRequest req;
        req.set_uri(uri ? uri : "");
        req.set_line(line);
        req.set_character(character);
        janus::oracle::HoverAtResponse resp;
        grpc::ClientContext ctx;
        ctx.set_deadline(std::chrono::system_clock::now() + std::chrono::milliseconds(client->rpc_timeout_ms));
        auto status = client->stub->HoverAt(&ctx, req, &resp);
        if (!status.ok()) {
            if (status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED) return 5;
            return 2;
        }
        if (markdown_out) *markdown_out = dup_cstr(resp.markdown());
        return 0;
    } catch (...) {
        return 3;
    }
}

extern "C" int janus_oracle_definition_at(JanusOracleClient* client,
                                           const char* uri,
                                           uint32_t line,
                                           uint32_t character,
                                           bool* found_out,
                                           const char** uri_out,
                                           uint32_t* def_line_out,
                                           uint32_t* def_character_out) {
    if (uri_out) *uri_out = nullptr;
    if (found_out) *found_out = false;
    if (!client || !client->stub) return 1;
    try {
        janus::oracle::PositionRequest req;
        req.set_uri(uri ? uri : "");
        req.set_line(line);
        req.set_character(character);
        janus::oracle::DefinitionAtResponse resp;
        grpc::ClientContext ctx;
        ctx.set_deadline(std::chrono::system_clock::now() + std::chrono::milliseconds(client->rpc_timeout_ms));
        auto status = client->stub->DefinitionAt(&ctx, req, &resp);
        if (!status.ok()) {
            if (status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED) return 5;
            return 2;
        }
        if (found_out) *found_out = resp.found();
        if (resp.found()) {
            if (uri_out) *uri_out = dup_cstr(resp.uri());
            if (def_line_out) *def_line_out = resp.line();
            if (def_character_out) *def_character_out = resp.character();
        }
        return 0;
    } catch (...) {
        return 3;
    }
}

extern "C" int janus_oracle_references_at(JanusOracleClient* client,
                                           const char* uri,
                                           uint32_t line,
                                           uint32_t character,
                                           bool include_declaration,
                                           JanusOracleLocation** locations_out,
                                           uint32_t* count_out) {
    if (locations_out) *locations_out = nullptr;
    if (count_out) *count_out = 0;
    if (!client || !client->stub) return 1;
    try {
        janus::oracle::ReferencesAtRequest req;
        req.set_uri(uri ? uri : "");
        req.set_line(line);
        req.set_character(character);
        req.set_include_declaration(include_declaration);
        janus::oracle::ReferencesAtResponse resp;
        grpc::ClientContext ctx;
        ctx.set_deadline(std::chrono::system_clock::now() + std::chrono::milliseconds(client->rpc_timeout_ms));
        auto status = client->stub->ReferencesAt(&ctx, req, &resp);
        if (!status.ok()) {
            if (status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED) return 5;
            return 2;
        }
        const auto n = static_cast<uint32_t>(resp.locations_size());
        if (n == 0) return 0;
        JanusOracleLocation* arr = static_cast<JanusOracleLocation*>(malloc(sizeof(JanusOracleLocation) * n));
        if (!arr) return 3;
        for (uint32_t i = 0; i < n; ++i) {
            const auto& loc = resp.locations(static_cast<int>(i));
            arr[i].uri = dup_cstr(loc.uri());
            arr[i].line = loc.line();
            arr[i].character = loc.character();
        }
        if (locations_out) *locations_out = arr;
        if (count_out) *count_out = n;
        return 0;
    } catch (...) {
        return 4;
    }
}

#include <thread>

struct JanusOracleServer {
    std::string host;
    uint16_t port;
    std::unique_ptr<grpc::Server> server;

    // Handlers
    JanusDocUpdateFn on_doc_update = nullptr;
    JanusHoverAtFn on_hover_at = nullptr;
    JanusDefinitionAtFn on_definition_at = nullptr;
    JanusReferencesAtFn on_references_at = nullptr;
    void* user = nullptr;

    struct ServiceImpl final : public janus::oracle::Oracle::Service {
        JanusOracleServer* owner;
        explicit ServiceImpl(JanusOracleServer* o) : owner(o) {}

        grpc::Status DocUpdate(grpc::ServerContext* ctx,
                               const janus::oracle::DocUpdateRequest* req,
                               janus::oracle::DocUpdateResponse* resp) override {
            (void)ctx;
            if (!owner->on_doc_update) return grpc::Status(grpc::StatusCode::UNIMPLEMENTED, "no handler");
            bool ok = false;
            int rc = owner->on_doc_update(req->uri().c_str(), req->content().c_str(), &ok, owner->user);
            if (rc != 0) return grpc::Status(grpc::StatusCode::INTERNAL, "handler error");
            resp->set_ok(ok);
            return grpc::Status::OK;
        }

        grpc::Status HoverAt(grpc::ServerContext* ctx,
                             const janus::oracle::PositionRequest* req,
                             janus::oracle::HoverAtResponse* resp) override {
            (void)ctx;
            if (!owner->on_hover_at) return grpc::Status(grpc::StatusCode::UNIMPLEMENTED, "no handler");
            const char* md = nullptr;
            int rc = owner->on_hover_at(req->uri().c_str(), req->line(), req->character(), &md, owner->user);
            if (rc != 0) return grpc::Status(grpc::StatusCode::INTERNAL, "handler error");
            if (md) resp->set_markdown(md);
            return grpc::Status::OK;
        }

        grpc::Status DefinitionAt(grpc::ServerContext* ctx,
                                  const janus::oracle::PositionRequest* req,
                                  janus::oracle::DefinitionAtResponse* resp) override {
            (void)ctx;
            if (!owner->on_definition_at) return grpc::Status(grpc::StatusCode::UNIMPLEMENTED, "no handler");
            bool found = false; const char* def_uri = nullptr; uint32_t line = 0; uint32_t ch = 0;
            int rc = owner->on_definition_at(req->uri().c_str(), req->line(), req->character(), &found, &def_uri, &line, &ch, owner->user);
            if (rc != 0) return grpc::Status(grpc::StatusCode::INTERNAL, "handler error");
            resp->set_found(found);
            if (found) {
                if (def_uri) resp->set_uri(def_uri);
                resp->set_line(line);
                resp->set_character(ch);
            }
            return grpc::Status::OK;
        }

        static void sink_to_response(void* sink_user, const char* uri, uint32_t line, uint32_t character) {
            auto* resp = static_cast<janus::oracle::ReferencesAtResponse*>(sink_user);
            auto* loc = resp->add_locations();
            if (uri) loc->set_uri(uri);
            loc->set_line(line);
            loc->set_character(character);
        }

        grpc::Status ReferencesAt(grpc::ServerContext* ctx,
                                  const janus::oracle::ReferencesAtRequest* req,
                                  janus::oracle::ReferencesAtResponse* resp) override {
            (void)ctx;
            if (!owner->on_references_at) return grpc::Status(grpc::StatusCode::UNIMPLEMENTED, "no handler");
            int rc = owner->on_references_at(req->uri().c_str(), req->line(), req->character(), req->include_declaration(), sink_to_response, resp, owner->user);
            if (rc != 0) return grpc::Status(grpc::StatusCode::INTERNAL, "handler error");
            return grpc::Status::OK;
        }
    };

    std::unique_ptr<ServiceImpl> service;
};

extern "C" JanusOracleServer* janus_oracle_server_create(const char* host, uint16_t port) {
    try {
        auto* s = new (std::nothrow) JanusOracleServer{};
        if (!s) return nullptr;
        s->host = host ? host : "127.0.0.1";
        s->port = port;
        s->service = std::make_unique<JanusOracleServer::ServiceImpl>(s);
        return s;
    } catch (...) {
        return nullptr;
    }
}

extern "C" void janus_oracle_server_destroy(JanusOracleServer* server) {
    if (!server) return;
    (void)janus_oracle_server_stop(server);
    delete server;
}

extern "C" int janus_oracle_server_set_handlers(JanusOracleServer* server,
                                                 JanusDocUpdateFn on_doc_update,
                                                 JanusHoverAtFn on_hover_at,
                                                 JanusDefinitionAtFn on_definition_at,
                                                 JanusReferencesAtFn on_references_at,
                                                 void* user) {
    if (!server) return 1;
    server->on_doc_update = on_doc_update;
    server->on_hover_at = on_hover_at;
    server->on_definition_at = on_definition_at;
    server->on_references_at = on_references_at;
    server->user = user;
    return 0;
}

extern "C" int janus_oracle_server_start(JanusOracleServer* server) {
    if (!server) return 1;
    try {
        std::string address = server->host + ":" + std::to_string(server->port);
        grpc::ServerBuilder builder;
        builder.AddListeningPort(address, grpc::InsecureServerCredentials());
        builder.RegisterService(server->service.get());
        server->server = builder.BuildAndStart();
        if (!server->server) return 2;
        // Non-blocking: run server in background thread detached
        std::thread([srv = server->server.get()](){ srv->Wait(); }).detach();
        return 0;
    } catch (...) {
        return 3;
    }
}

extern "C" int janus_oracle_server_stop(JanusOracleServer* server) {
    if (!server) return 1;
    if (server->server) {
        server->server->Shutdown();
        server->server.reset();
    }
    return 0;
}

#else // !HAVE_JANUS_ORACLE_GRPC_STUBS

// Fallback stub implementations: compile and always fail gracefully, keeping the build green.

struct JanusOracleClient { int unused; };

extern "C" JanusOracleClient* janus_oracle_client_connect(const char* /*host*/, uint16_t /*port*/) {
    return nullptr; // gRPC stubs unavailable; transport not available in this build
}

extern "C" void janus_oracle_client_disconnect(JanusOracleClient* /*client*/) {}

extern "C" void janus_oracle_free_string(const char* s) { (void)s; }

extern "C" int janus_oracle_doc_update(JanusOracleClient* /*client*/, const char* /*uri*/, const char* /*content*/, bool* ok_out) {
    if (ok_out) *ok_out = false; return 1;
}

extern "C" int janus_oracle_hover_at(JanusOracleClient* /*client*/, const char* /*uri*/, uint32_t /*line*/, uint32_t /*character*/, const char** markdown_out) {
    if (markdown_out) *markdown_out = nullptr; return 1;
}

extern "C" int janus_oracle_definition_at(JanusOracleClient* /*client*/, const char* /*uri*/, uint32_t /*line*/, uint32_t /*character*/, bool* found_out, const char** uri_out, uint32_t* def_line_out, uint32_t* def_character_out) {
    if (found_out) *found_out = false; if (uri_out) *uri_out = nullptr; if (def_line_out) *def_line_out = 0; if (def_character_out) *def_character_out = 0; return 1;
}

extern "C" int janus_oracle_references_at(JanusOracleClient* /*client*/, const char* /*uri*/, uint32_t /*line*/, uint32_t /*character*/, bool /*include_declaration*/, JanusOracleLocation** locations_out, uint32_t* count_out) {
    if (locations_out) *locations_out = nullptr; if (count_out) *count_out = 0; return 1;
}

struct JanusOracleServer { int unused; };
extern "C" JanusOracleServer* janus_oracle_server_create(const char* /*host*/, uint16_t /*port*/) { return nullptr; }
extern "C" void janus_oracle_server_destroy(JanusOracleServer* /*server*/) {}
extern "C" int janus_oracle_server_set_handlers(JanusOracleServer* /*server*/, JanusDocUpdateFn, JanusHoverAtFn, JanusDefinitionAtFn, JanusReferencesAtFn, void* /*user*/) { return 1; }
extern "C" int janus_oracle_server_start(JanusOracleServer* /*server*/) { return 1; }
extern "C" int janus_oracle_server_stop(JanusOracleServer* /*server*/) { return 0; }

#endif // HAVE_JANUS_ORACLE_GRPC_STUBS
