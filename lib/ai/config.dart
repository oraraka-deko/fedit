// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


class Config {
  String apiKey = '';
  String baseUrl = '';
  String proxyUrl = "";
  String currentModel = '';
  bool autoAccept = true;
  bool firstSetup = true;
  List<String> hiddenIncludePatterns = [];
  List<String> hiddenExcludePatterns = [];

  static final ValueNotifier<int> _reloadNotifier = ValueNotifier(0);

  /// Fires whenever something explicitly requests reloading the config.
  static Listenable get reloadNotifier => _reloadNotifier;

  /// Forces a config reload so listeners can react immediately.
  static Future<void> forceReload() async {
    _reloadNotifier.value++;
  }

  static Future<Config> load() async {
    final path = _getConfigPath();
    final file = File(await path);
    if (!await file.exists()) return Config();

    try {
      final content = await file.readAsString();
      final map = jsonDecode(content);
      return Config()
        ..apiKey = map['api_key'] ?? ''
        ..baseUrl = map['base_url'] ?? ''
        ..proxyUrl = map['proxy_url'] ?? ""
        ..currentModel = map['current_model'] ?? ''
        ..autoAccept = map['auto_accept'] ?? false
        ..firstSetup = map['first_setup'] ?? false
        ..hiddenIncludePatterns = _stringList(map['hidden_include'])
        ..hiddenExcludePatterns = _stringList(map['hidden_exclude']);
    } catch (_) {
      return Config();
    }
  }

  Future<void> save() async {
    final path = _getConfigPath();
    final file = File(await path);
    await file.parent.create(recursive: true);
    final encoder = JsonEncoder.withIndent("  ");
    await file.writeAsString(
      encoder.convert({
        'api_key': apiKey,
        'base_url': baseUrl,
        'proxy_url': proxyUrl,
        'current_model': currentModel,
        'auto_accept': autoAccept,
        'first_setup': firstSetup,
        'hidden_include': hiddenIncludePatterns,
        'hidden_exclude': hiddenExcludePatterns,
      }),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static Future<String> _getConfigPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Use internal app storage (application support directory)
      final appDir = await getApplicationSupportDirectory();
      final configDir = Directory(p.join(appDir.path, 'ai2dart'));
      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
      }
      final configFile = File(p.join(configDir.path, 'config.json'));
      if (!configFile.existsSync()) {
        configFile.createSync();
      }
      return configFile.path;
    } else {
      // Existing behavior for desktop platforms
      final home = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'];
      final configDirPath = p.join(home!, '.config', 'ai2dart');
      final configDir = Directory(configDirPath);
      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
      }
      final configFilePath = p.join(configDirPath, 'config.json');
      final configFile = File(configFilePath);
      if (!configFile.existsSync()) {
        configFile.createSync();
      }
      return configFilePath;
    }
  }
}

// UI Editor Widget
class ConfigEditor extends StatefulWidget {
  const ConfigEditor({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ConfigEditorState createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<ConfigEditor> {
  late Config config;
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _proxyUrlController;
  late TextEditingController _currentModelController;
  late TextEditingController _hiddenIncludeController;
  late TextEditingController _hiddenExcludeController;
  bool _autoAccept = true;
  bool _firstSetup = true;
  List<String> _availableModels = [];
  String? _selectedModel;
  bool _isFetchingModels = false;
  bool _allowCustomModel = false;
  bool _userInteractedWithModelSelection = false;
  String? _modelFetchError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    String? loadError;
    try {
      config = await Config.load();
    } catch (e) {
      loadError = e.toString();
      config = Config();
    }

    _apiKeyController = TextEditingController(text: config.apiKey);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _proxyUrlController = TextEditingController(text: config.proxyUrl);
    _currentModelController = TextEditingController(text: config.currentModel);
    _hiddenIncludeController = TextEditingController(
      text: config.hiddenIncludePatterns.join('\n'),
    );
    _hiddenExcludeController = TextEditingController(
      text: config.hiddenExcludePatterns.join('\n'),
    );
    _autoAccept = config.autoAccept;
    _firstSetup = config.firstSetup;
    _selectedModel =
        config.currentModel.isNotEmpty ? config.currentModel : null;
    _allowCustomModel = false;
    _userInteractedWithModelSelection = false;

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (loadError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load config: $loadError')),
      );
    }

    await _fetchModelList();
  }

  Future<void> _fetchModelList() async {
    if (!mounted) return;
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _availableModels = [];
          _selectedModel = null;
          _allowCustomModel = true;
          _modelFetchError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isFetchingModels = true;
        _modelFetchError = null;
      });
    }

    try {
      final uri = Uri.parse(baseUrl).resolve('v1/models');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode != 200) {
        throw Exception('Server responded with ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final decodedMap =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final rawModels = (decodedMap['data'] as List<dynamic>?) ?? [];
      final models = rawModels
          .map((entry) =>
              entry is Map<String, dynamic> ? entry['id'] : entry)
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _modelFetchError = null;

        if (models.isEmpty) {
          _selectedModel = null;
          if (!_userInteractedWithModelSelection) {
            _allowCustomModel = true;
          }
          return;
        }

        if (_selectedModel == null || !models.contains(_selectedModel)) {
          _selectedModel = models.first;
        }

        final savedModel = config.currentModel;
        final savedInList =
            savedModel.isNotEmpty && models.contains(savedModel);
        if (!_userInteractedWithModelSelection) {
          if (savedInList) {
            _selectedModel = savedModel;
            _allowCustomModel = false;
          } else if (savedModel.isNotEmpty &&
              _currentModelController.text.trim() == savedModel) {
            _allowCustomModel = true;
            _currentModelController.text = savedModel;
          } else {
            _allowCustomModel = false;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableModels = [];
        _selectedModel = null;
        _allowCustomModel = true;
        _modelFetchError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch models: $e')),
      );
    } finally {
      // ignore: control_flow_in_finally
      if (!mounted) return;
      setState(() {
        _isFetchingModels = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    config.apiKey = _apiKeyController.text;
    config.baseUrl = _baseUrlController.text;
    config.proxyUrl = _proxyUrlController.text;
    final useCustomModel = _allowCustomModel || _availableModels.isEmpty;
    config.currentModel = useCustomModel
        ? _currentModelController.text.trim()
        : (_selectedModel ?? _currentModelController.text).trim();
    config.autoAccept = _autoAccept;
    config.firstSetup = _firstSetup;
    config.hiddenIncludePatterns = _parseLines(_hiddenIncludeController.text);
    config.hiddenExcludePatterns = _parseLines(_hiddenExcludeController.text);

    try {
      await config.save();
      await Config.forceReload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save config: $e')));
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _proxyUrlController.dispose();
    _currentModelController.dispose();
    _hiddenIncludeController.dispose();
    _hiddenExcludeController.dispose();
    super.dispose();
  }

  List<String> _parseLines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Config Editor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an API key';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrlController,
                decoration: const InputDecoration(labelText: 'Base URL'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a base URL';
                  }
                  if (!Uri.tryParse(value)!.isAbsolute) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _proxyUrlController,
                decoration: const InputDecoration(
                  labelText: 'Proxy URL (optional)',
                ),
              ),
              const SizedBox(height: 16),
              if (_availableModels.isNotEmpty && !_allowCustomModel)
                DropdownButtonFormField<String>(
                  value: _selectedModel ?? _availableModels.first,
                  decoration: const InputDecoration(labelText: 'Current Model'),
                  isExpanded: true,
                  items: _availableModels
                      .map(
                        (model) => DropdownMenuItem(
                          value: model,
                          child: Text(model, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedModel = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a model';
                    }
                    return null;
                  },
                ),
              if (_allowCustomModel || _availableModels.isEmpty)
                TextFormField(
                  controller: _currentModelController,
                  decoration: const InputDecoration(labelText: 'Current Model'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a model name';
                    }
                    return null;
                  },
                ),
              if (_availableModels.isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Use custom model name'),
                  value: _allowCustomModel,
                  onChanged: (value) {
                    setState(() {
                      _allowCustomModel = value;
                      _userInteractedWithModelSelection = value;
                      if (value && _selectedModel != null) {
                        _currentModelController.text = _selectedModel!;
                      }
                    });
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isFetchingModels ? null : _fetchModelList,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh models'),
                  ),
                ),
                if (_isFetchingModels)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: LinearProgressIndicator(),
                  ),
                if (_modelFetchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _modelFetchError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Auto Accept'),
                value: _autoAccept,
                onChanged: (value) => setState(() => _autoAccept = value),
              ),
              const SizedBox(height: 16),
              const Text(
                'AI File Filters',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _hiddenExcludeController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Hide patterns (one per line)',
                  hintText: 'node_modules/\n**/*.log\nbuild/\n.venv/',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hiddenIncludeController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Always include patterns (override)',
                  hintText: 'build/keep/**\n**/README.md',
                ),
              ),
              SwitchListTile(
                title: const Text('First Setup'),
                value: _firstSetup,
                onChanged: (value) => setState(() => _firstSetup = value),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saveConfig,
                child: const Text('Save Config'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
