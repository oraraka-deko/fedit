// ignore_for_file: unused_local_variable

import 'dart:convert';
import 'api.dart';
import 'config.dart';
import 'tools_handler.dart';
import 'models.dart' as m;

/// Configuration for a specific Agent "Minion".
/// This allows us to use the same Model (e.g. GPT-4o) but with different
/// "Personalities" and "Constraints" (e.g. max tokens) to save costs.
class AgentConfig {
  final String agentName;
  final String systemPrompt;
  final int maxOutputTokens;
  final double temperature;
  final bool jsonMode;
  final List<String> allowedTools; // If empty, allow all (or none, depending on policy)

  AgentConfig({
    required this.agentName,
    required this.systemPrompt,
    this.maxOutputTokens = 1024, // Default "Cost of cheap ice cream" constraint
    this.temperature = 0.0,      // Strict by default
    this.jsonMode = false,       // If true, forces JSON object output
    this.allowedTools = const [],
  });
}

/// The Base Contract for all Game-Element Agents.
/// Every Agent (Washer, Orchestrator, Admin, Main) must follow this.
abstract class AgentBase {
  final ApiClient apiClient;
  final AgentConfig agentConfig;
  final ToolsHandler toolsHandler;

  // Internal history for this specific agent instance.
  // We keep this separate from the main ChatService history.
  List<Message> history = [];

  AgentBase({
    required this.apiClient,
    required this.agentConfig,
    required this.toolsHandler,
  }) {
    // Initialize with the System Prompt (The Agent's "Mission")
    history.add(Message(role: "system", content: agentConfig.systemPrompt));
  }

  /// 1. Message: Sends a single message and gets a raw response.
  /// Does NOT automatically execute tools. Just thinking.
  Future<Message> message(String userContent) async {
    history.add(Message(role: "user", content: userContent));
    
    // We construct the tool definitions dynamically based on allowedTools
    // If allowedTools is empty, we might pass all, or none. 
    // For now, let's assume we pass what the ToolsHandler has.
    final List<m.Tool> tools = toolsHandler.getToolDefinitions()
        .where((t) => agentConfig.allowedTools.isEmpty || 
                      agentConfig.allowedTools.contains(t.function['name']))
        .toList();

    // We use a stream but buffer it to get the full response for this method
    final stream = apiClient.runCompletionStream(
      history, 
      tools, 
      Config().currentModel // Or override per agent if needed
    );

    String buffer = "";
    List<ToolCall> accumulatedToolCalls = [];
    
    // Simple stream consumption for single-turn logic
    await for (final chunk in stream) {
      if (chunk.content != null) buffer += chunk.content!;
      // Note: Tool call assembly logic from ChatService would theoretically go here
      // but for this base class abstraction, we assume ApiClient or a helper
      // helps assemble chunks. For simplicity in this new file, we simulate
      // that the ApiClient handles the full assembly or we reconstruct it here.
      // (Omitting complex stream re-assembly for brevity, strictly following your architecture request).
    }

    final responseMsg = Message(role: "assistant", content: buffer);
    history.add(responseMsg);
    return responseMsg;
  }

  /// 2. MessageLoop: The Agent "Thinks" until it is satisfied.
  /// Useful for Agents that need to self-correct (e.g. Washer checking its own work).
  Future<String> messageLoop(String userContent, {int maxTurns = 3}) async {
    await message(userContent);
    
    int turns = 0;
    while(turns < maxTurns) {
      // Internal logic to check if done. 
      // For a Washer agent, it might look at its own JSON output.
      // If valid, return. If invalid, send error to self and retry.
      
      // Placeholder: In a real implementation, we analyze history.last
      break; 
    }
    return history.last.content ?? "";
  }

  /// 3. MessageToolCall: Sends message, expects a Tool Call back.
  /// Returns the ToolCall object, does NOT execute it yet.
  Future<ToolCall?> messageToolCall(String userContent) async {
    final response = await message(userContent);
    if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
      return response.toolCalls!.first;
    }
    return null;
  }

  /// 4. MessageToolCallRespondSingle: Executes a specific tool and returns result to Agent.
  Future<String> messageToolCallRespondSingle(ToolCall call) async {
    // Execute logic
    String result;
    try {
      final args = jsonDecode(call.function.arguments);
      
      // Hook: Allow Admin agents to intercept 'batch' calls here
      if (this is AgentAdmin && call.function.name.startsWith("batch_")) {
        result = await (this as AgentAdmin).executeBatchTool(call.function.name, args);
      } else {
        result = await toolsHandler.execute(call.function.name, args);
      }
    } catch (e) {
      result = "Error executing tool: $e";
    }

    // Feed result back to history
    history.add(Message(
      role: "tool",
      content: result,
      toolCallId: call.id,
    ));

    // Get Agent's reaction to the tool result
    // We trigger a completion generation without new user input
    // strictly to let the AI process the tool result.
    // (Implementation depends on ApiClient supporting empty user prompt trigger)
    return result;
  }

  /// 5. MessageToolCallRespondLoop: The "Autonomy" loop.
  /// Agent gets task -> Calls Tool -> Gets Result -> Calls Next Tool -> ... -> Finish.
  Future<void> messageToolCallRespondLoop(String userContent, {int maxSteps = 5}) async {
    history.add(Message(role: "user", content: userContent));
    
    int steps = 0;
    bool keepGoing = true;

    while (keepGoing && steps < maxSteps) {
      // 1. Ask AI
      // (Re-using logic similar to message() but ensuring we pass tools)
      final tools = toolsHandler.getToolDefinitions(); 
      final stream = apiClient.runCompletionStream(history, tools, Config().currentModel);
      
      // ... buffer response ...
      // If response has tool calls -> execute them -> add result -> loop
      // If response has text only -> we are done -> keepGoing = false
      steps++;
      // Simplified for architecture demo
      keepGoing = false; 
    }
  }
}

/// ===========================================================================
/// THE AGENT ADMIN (The Boss)
/// ===========================================================================
/// This Agent has special privileges. It handles BATCH operations.
/// It doesn't look at "Context History" of files. It looks at "Tasks".
/// 
/// Example: "Rename variable X in these 5 files"
/// Standard Agent: Reads 5 files (Huge tokens), Patches 5 files (Huge tokens).
/// Agent Admin: Receives list of 5 paths. Calls 'batch_patch'. (Tiny tokens).
class AgentAdmin extends AgentBase {
  
  AgentAdmin({
    required super.apiClient, 
    required super.toolsHandler,
  }) : super(
    agentConfig: AgentConfig(
      agentName: "Admin",
      // "Einstein Brain, Cheap Ice Cream" strategy:
      // We explicitly tell it NOT to be chatty. Just Output Actions.
      systemPrompt: 
        "You are the ADMIN AGENT. You do not chat. You execute BATCH operations.\n"
        "Input: High-level architectural instructions or refactoring tasks.\n"
        "Output: JSON Tool Calls for batch_patch, batch_create, or file_action.\n"
        "Constraint: Return minimal acknowledgement. Focus on Tool Calls.",
      maxOutputTokens: 2048, // Allow enough tokens for a complex Batch JSON, but restricts yapping.
      temperature: 0.1,      // Precision is required for Admin work.
      allowedTools: [
        "list_files", 
        "read_file", 
        "batch_patch",   // Special Admin Tool
        "batch_create",  // Special Admin Tool
        "file_action"
      ], 
    )
  );

  /// SPECIAL: Admin-specific tool execution logic.
  /// This bypasses the standard ToolsHandler for batch operations to optimize IO.
  Future<String> executeBatchTool(String name, Map<String, dynamic> args) async {
    StringBuffer report = StringBuffer();
    
    if (name == "batch_patch") {
      // Schema: { "operations": [ { "path": "...", "patch": "..." }, ... ] }
      final ops = args['operations'] as List?;
      if (ops == null) return "Error: 'operations' list required for batch_patch";

      report.writeln("Executed Batch Patch:");
      for (var op in ops) {
        String path = op['path'];
        String patch = op['patch'];
        try {
          // Re-use the existing atomic logic but wrapped in batch
          // We can access private methods if we refactor ToolsHandler, 
          // or just call the public execute for now.
          String result = await toolsHandler.execute('patch_file', {'path': path, 'patch': patch});
          report.writeln("- $path: $result");
        } catch (e) {
          report.writeln("- $path: [FAILED] $e");
        }
      }
    } 
    
    else if (name == "batch_create") {
      // Schema: { "files": [ { "path": "...", "content": "..." }, ... ] }
      final files = args['files'] as List?;
      if (files == null) return "Error: 'files' list required for batch_create";

      report.writeln("Executed Batch Create:");
      for (var f in files) {
        String path = f['path'];
        // String content = f['content']; 
        // Logic to create file...
        try {
          // Using existing tool logic
          String result = await toolsHandler.execute('file_action', {'action': 'create', 'path': path});
          // Note: Standard file_action create doesn't take content yet in your current code,
          // so the Admin would need to write content separately or we upgrade file_action.
          // For now, we assume simple creation.
          report.writeln("- $path: $result");
        } catch (e) {
          report.writeln("- $path: [FAILED] $e");
        }
      }
    }

    return report.toString();
  }

  /// Override to inject the Batch Tools into the definitions sent to the LLM
  @override
  Future<Message> message(String userContent) async {
    // We temporally inject "batch_patch" and "batch_create" into the allowed tools schema
    // just for the Admin agent context.
    // In a real implementation, we'd append these schemas to the ToolsHandler output here.
    return super.message(userContent);
  }
}