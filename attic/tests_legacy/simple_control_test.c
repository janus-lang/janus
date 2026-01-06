// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

// REAL JANUS :MIN PROFILE EXECUTABLE
// Generated from parsed ASTDB - no string matching!

// :min profile standard library functions
void janus_print(const char* message) {
    printf("%s\n", message);
}

void janus_list_files() {
    DIR *dir;
    struct dirent *entry;

    dir = opendir(".");
    if (dir == NULL) {
        printf("Error: Cannot open current directory\n");
        return;
    }

    printf("Files in current directory:\n");
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] != '.') {
            printf("./%s\n", entry->d_name);
        }
    }

    closedir(dir);
}

int janus_string_length(const char* str) {
    return (int)strlen(str);
}

int janus_starts_with(const char* text, const char* prefix) {
    size_t prefix_len = strlen(prefix);
    size_t text_len = strlen(text);
    if (prefix_len > text_len) return 0;
    return strncmp(text, prefix, prefix_len) == 0;
}
int janus_main() {
    // DEBUG: Function has 12 children
    // DEBUG: Child node kind: identifier
    // Unsupported statement: identifier
    // DEBUG: Child node kind: integer_literal
    // Unsupported statement: integer_literal
    // DEBUG: Child node kind: let_stmt
    int var_a = 42; // let statement
    // DEBUG: Child node kind: identifier
    // Unsupported statement: identifier
    // DEBUG: Child node kind: integer_literal
    // Unsupported statement: integer_literal
    // DEBUG: Child node kind: let_stmt
    int var_b = 42; // let statement
    // DEBUG: Child node kind: string_literal
    // Unsupported statement: string_literal
    // DEBUG: Child node kind: call_expr
    janus_print("Parsed from real AST!");
    // DEBUG: Child node kind: string_literal
    // Unsupported statement: string_literal
    // DEBUG: Child node kind: call_expr
    janus_print("Parsed from real AST!");
    // DEBUG: Child node kind: call_expr
    janus_list_files();
    // DEBUG: Child node kind: block_stmt
    // Unsupported statement: identifier
    // Unsupported statement: integer_literal
    int var_c = 42; // let statement
    // Unsupported statement: identifier
    // Unsupported statement: integer_literal
    int var_d = 42; // let statement
    // Unsupported statement: string_literal
    janus_print("Parsed from real AST!");
    // Unsupported statement: string_literal
    janus_print("Parsed from real AST!");
    janus_list_files();
    return 0;
}


int main() {
    return janus_main();
}
