import 'package:face_att/pages/classes/create_class_screen.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/services/face_recognition/arcface_embedding_service.dart';
import 'package:face_att/services/face_recognition/model_manager_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Screen presented on first app setup when models are not bundled,
/// or accessible from Settings to manage and switch face recognition models.
class ModelSetupScreen extends StatefulWidget {
  final bool isFirstRun;
  final bool hasClasses;
  final VoidCallback? onSetupComplete;

  const ModelSetupScreen({
    super.key,
    this.isFirstRun = true,
    this.hasClasses = false,
    this.onSetupComplete,
  });

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  final ModelManagerService _modelManager = ModelManagerService.instance;
  final ArcFaceEmbeddingService _embeddingService = ArcFaceEmbeddingService();

  late ModelDescriptor _selectedModel;
  bool _isDownloading = false;
  bool _isImporting = false;
  String? _errorMessage;
  ModelDownloadProgress? _downloadProgress;
  DownloadCancellationToken? _cancellationToken;

  List<ModelStatus> _installedModels = [];
  bool _isLoadingInstalled = true;

  @override
  void initState() {
    super.initState();
    _selectedModel = ModelManagerService.supportedModels.first;
    _loadInstalledModels();
  }

  Future<void> _loadInstalledModels() async {
    try {
      final list = await _modelManager.getInstalledModels();
      if (mounted) {
        setState(() {
          _installedModels = list;
          _isLoadingInstalled = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingInstalled = false);
      }
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _downloadProgress = null;
      _cancellationToken = DownloadCancellationToken();
    });

    try {
      await _modelManager.downloadModel(
        _selectedModel,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
        cancellationToken: _cancellationToken,
      );

      // Re-initialize embedding interpreter with new model
      await _embeddingService.initializeInterpreter();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedModel.name} initialized successfully.'),
            backgroundColor: AppColors.present,
          ),
        );
        _handleSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isDownloading = false;
        });
      }
    }
  }

  void _cancelDownload() {
    _cancellationToken?.cancel();
    setState(() {
      _isDownloading = false;
      _downloadProgress = null;
      _errorMessage = 'Download cancelled.';
    });
  }

  Future<void> _pickModelManually() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final file = await _modelManager.pickAndImportModelFile();
      if (file == null) {
        setState(() => _isImporting = false);
        return;
      }

      await _embeddingService.initializeInterpreter();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model imported and initialized: ${file.path.split('/').last}'),
            backgroundColor: AppColors.present,
          ),
        );
        _handleSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isImporting = false;
        });
      }
    }
  }

  void _handleSuccess() {
    if (widget.isFirstRun) {
      if (widget.onSetupComplete != null) {
        widget.onSetupComplete!();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => widget.hasClasses
                ? const HomeScreen()
                : const CreateClassScreen(isFirstRun: true),
          ),
        );
      }
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstRun ? 'Face Recognition Setup' : 'Manage Models'),
        automaticallyImplyLeading: !widget.isFirstRun,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Header Hero Card
            _buildHeaderCard(colorScheme),
            const SizedBox(height: 20),

            // If already installed models exist and not first run, show current status
            if (!widget.isFirstRun && !_isLoadingInstalled && _installedModels.isNotEmpty) ...[
              _buildInstalledSection(colorScheme),
              const SizedBox(height: 24),
            ],

            // Section 1: Automatic Download
            _buildDownloadSection(colorScheme),
            const SizedBox(height: 24),

            // Section 2: Manual File Selection
            _buildManualImportSection(colorScheme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.psychology_outlined,
              size: 28,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On-Device AI Model',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Local Attendance operates entirely offline with zero cloud telemetry. To recognize student faces, an ArcFace ONNX neural network model is required on this device.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Installed Models on Device',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        ..._installedModels.map((m) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: m.isActive
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: m.isActive ? 2 : 1,
              ),
            ),
            child: ListTile(
              leading: Icon(
                m.isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                color: m.isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              title: Text(
                m.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                '${m.sourceLabel} • ${m.formattedSize}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              trailing: m.source == ModelSourceType.downloaded && !m.isActive
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        await _modelManager.deleteModel(m.id);
                        _loadInstalledModels();
                      },
                    )
                  : null,
              onTap: () async {
                if (!m.isActive) {
                  await _modelManager.setActiveModel(m);
                  await _embeddingService.initializeInterpreter();
                  _loadInstalledModels();
                }
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDownloadSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_download_outlined, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Option 1: Download Model (Recommended)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select a model to download directly from verified AI repositories:',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          // Model Options Radio Cards
          ...ModelManagerService.supportedModels.map((model) {
            final isSelected = _selectedModel.id == model.id;
            return InkWell(
              onTap: _isDownloading
                  ? null
                  : () {
                      setState(() => _selectedModel = model);
                    },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Radio<String>(
                      value: model.id,
                      groupValue: _selectedModel.id,
                      onChanged: _isDownloading
                          ? null
                          : (val) {
                              if (val != null) setState(() => _selectedModel = model);
                            },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                model.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: model.isDefault
                                      ? colorScheme.primary.withValues(alpha: 0.15)
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  model.isDefault ? 'Recommended • ${model.formattedSize}' : model.formattedSize,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: model.isDefault ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            model.description,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Error Message Display
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 20, color: colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Download Progress Bar
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _downloadProgress?.progressPercent,
              backgroundColor: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _downloadProgress != null
                      ? '${_downloadProgress!.formattedReceived} / ${_downloadProgress!.formattedTotal} (${(_downloadProgress!.progressPercent * 100).toStringAsFixed(0)}%)'
                      : 'Connecting to repository...',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  _downloadProgress?.formattedSpeed ?? '',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _cancelDownload,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel Download'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download_rounded),
                label: Text('Download ${_selectedModel.name} (${_selectedModel.formattedSize})'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualImportSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_outlined, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Option 2: Select Model Manually',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Already have a compatible ArcFace ONNX model (.onnx) on your device storage, SD card, or local network? Select it to skip the download:',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isImporting || _isDownloading ? null : _pickModelManually,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_rounded),
              label: Text(_isImporting ? 'Verifying model file...' : 'Choose .onnx File from Device'),
            ),
          ),
        ],
      ),
    );
  }
}
