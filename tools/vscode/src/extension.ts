import * as path from 'path';
import * as fs from 'fs';
import { workspace, ExtensionContext, window } from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';
import { execSync } from 'child_process';

let client: LanguageClient | undefined;

function commandExists(cmd: string): boolean {
    try {
        execSync(`which ${cmd}`, { stdio: 'ignore' });
        return true;
    } catch {
        return false;
    }
}

export function activate(context: ExtensionContext) {
    // 1. Get configuration
    const config = workspace.getConfiguration('janus');
    const serverCommand = config.get<string>('lsp.serverPath') || 'janus-lsp';
    const serverArgs = config.get<string[]>('lsp.arguments') || [];

    // 2. Check if binary exists
    if (!commandExists(serverCommand)) {
        // LSP not available - syntax highlighting still works
        console.log(`Janus LSP: '${serverCommand}' not found in PATH. Syntax highlighting active, LSP disabled.`);
        return;
    }

    // 3. Define Server Options (Spawn the binary)
    const serverOptions: ServerOptions = {
        run: { command: serverCommand, args: serverArgs, transport: TransportKind.stdio },
        debug: { command: serverCommand, args: serverArgs, transport: TransportKind.stdio }
    };

    // 4. Define Client Options
    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'janus' }],
        synchronize: {
            fileEvents: workspace.createFileSystemWatcher('**/*.jan')
        }
    };

    // 5. Create and Start Client
    try {
        client = new LanguageClient(
            'janus',
            'Janus Language Server',
            serverOptions,
            clientOptions
        );
        client.start();
    } catch (err) {
        console.error('Janus LSP: Failed to start language server:', err);
    }
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
