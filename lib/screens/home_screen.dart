import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:markdown/markdown.dart' as md;
import '../providers/auth_provider.dart';
import '../providers/drive_provider.dart';
import '../widgets/youtube_syntax.dart';
import '../widgets/media_syntax.dart';
import '../utils/file_picker.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  String? _editingFileId;
  final _formKey = GlobalKey<FormState>();
  int _editorTabIndex = 0; // 0: Write, 1: Preview, 2: Split
  bool? _wasLastBuildLargeScreen;
  bool _isCreatingNew = false;
  final Set<String> _expandedFolderIds = {};
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    setState(() {}); // Rebuild to update preview in real-time
  }

  void _clearEditor() {
    setState(() {
      _titleController.clear();
      _contentController.clear();
      _editingFileId = null;
      _isCreatingNew = false;
      _editorTabIndex = _wasLastBuildLargeScreen == true ? 2 : 0;
    });
  }



  void _insertMarkdown(String prefix, {String suffix = ''}) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    int start = selection.start;
    int end = selection.end;
    
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    
    final selectedText = text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    
    final newText = text.replaceRange(start, end, replacement);
    
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selectedText.length,
      ),
    );
    
    _contentFocusNode.requestFocus();
  }

  MarkdownStyleSheet _getMarkdownStyleSheet(BuildContext context) {
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: GoogleFonts.inter(
        color: const Color(0xFFE2E8F0),
        fontSize: 14,
        height: 1.6,
      ),
      h1: GoogleFonts.outfit(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 22,
        height: 1.5,
      ),
      h2: GoogleFonts.outfit(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18,
        height: 1.5,
      ),
      h3: GoogleFonts.outfit(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 16,
        height: 1.5,
      ),
      code: GoogleFonts.firaCode(
        color: const Color(0xFF38BDF8),
        backgroundColor: const Color(0xFF0F172A),
        fontSize: 12.5,
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3394A3B8)),
      ),
      blockquote: GoogleFonts.inter(
        color: const Color(0xFF94A3B8),
        fontStyle: FontStyle.italic,
        fontSize: 14,
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF6366F1), width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
      listBullet: GoogleFonts.inter(
        color: const Color(0xFF06B6D4),
        fontSize: 14,
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x2294A3B8), width: 1),
        ),
      ),
      tableBorder: TableBorder.all(
        color: const Color(0x3394A3B8),
        width: 1,
      ),
      tableBody: GoogleFonts.inter(
        color: const Color(0xFFE2E8F0),
        fontSize: 13,
      ),
      tableHead: GoogleFonts.outfit(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      tableHeadAlign: TextAlign.left,
      tablePadding: const EdgeInsets.all(8),
    );
  }

  Future<void> _saveFile() async {
    if (!_formKey.currentState!.validate()) return;

    final driveState = ref.read(driveProvider.notifier);
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    try {
      if (_editingFileId != null) {
        await driveState.updateFile(_editingFileId!, content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File updated successfully!')),
          );
        }
      } else {
        final finalTitle = title.toLowerCase().endsWith('.md') ? title : '$title.md';
        final newFileId = await driveState.createFile(finalTitle, content, parentFolderId: _selectedFolderId);
        if (mounted && newFileId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File created successfully!')),
          );
          setState(() {
            _editingFileId = newFileId;
            _isCreatingNew = false;
          });
        }
      }
    } catch (e) {
      // Error is caught here, success snackbar will not be shown.
      // The error itself is already reported to the user via the DriveState listener.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final driveState = ref.watch(driveProvider);

    // Watch for error messages and display them
    ref.listen<DriveState>(driveProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      // Sync file contents when finished downloading
      if (_editingFileId != null &&
          next.fileContents.containsKey(_editingFileId) &&
          !(previous?.fileContents.containsKey(_editingFileId) ?? false)) {
        setState(() {
          _contentController.text = next.fileContents[_editingFileId]!;
        });
      }
    });

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });

    final isAuthorized = authState.user != null || authState.isOfflineMode;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate
      body: SafeArea(
        child: !isAuthorized
            ? _buildLoginScreen(context, authState, driveState)
            : _buildDashboard(context, authState, driveState),
      ),
    );
  }

  Widget _buildLoginScreen(BuildContext context, AuthState authState, DriveState driveState) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: const Color(0x1F334155), // Translucent slate
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(color: const Color(0x3394A3B8), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo/Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: const Icon(
                  Icons.cloud_sync,
                  size: 44,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // App Title
              Text(
                'CloudSync Docs',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              // Subtitle
              Text(
                'Sync your private notes seamlessly and securely inside your personal Google Drive account. No third-party servers.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF94A3B8),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Google Login Button
              if (authState.isLoading)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                )
              else ...[
                ElevatedButton(
                  onPressed: () => ref.read(authProvider.notifier).signIn(),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google Logo Icon (drawn customly or with text)
                      Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                        height: 22,
                        width: 22,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.login,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Sign In with Google',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                if (driveState.files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).enterOfflineMode(),
                    icon: const Icon(Icons.offline_pin_outlined, color: Color(0xFF06B6D4)),
                    label: Text(
                      'Continue Offline (View Cache)',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF06B6D4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, AuthState authState, DriveState driveState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 800;

        // Adaptive default editor tab index when transitioning screen sizes
        if (_wasLastBuildLargeScreen != isLargeScreen) {
          _wasLastBuildLargeScreen = isLargeScreen;
          _editorTabIndex = isLargeScreen ? 2 : 0;
        }

        return CustomScrollView(
          slivers: [
            // Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildHeader(context, authState, driveState),
              ),
            ),
            // Body Grid/List
            if (isLargeScreen)
              SliverFillRemaining(
                hasScrollBody: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildFileExplorer(context, driveState),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: _buildFileEditor(context, driveState),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildFileEditor(context, driveState),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      height: 500,
                      child: _buildFileExplorer(context, driveState),
                    ),
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AuthState authState, DriveState driveState) {
    final user = authState.user;
    final isOffline = authState.isOfflineMode;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0x12334155),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x1A94A3B8), width: 1),
      ),
      child: Row(
        children: [
          // App logo/sync indicator
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isOffline
                        ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                        : [const Color(0xFF6366F1), const Color(0xFF06B6D4)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline ? Icons.cloud_off : Icons.cloud_done,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              if (driveState.isLoading && !isOffline)
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CloudSync Docs',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  isOffline
                      ? 'Offline Mode (Viewing Cache)'
                      : (driveState.isLoading
                          ? 'Syncing with Google Drive...'
                          : 'Connected securely'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isOffline
                        ? const Color(0xFFF59E0B)
                        : (driveState.isLoading
                            ? const Color(0xFF06B6D4)
                            : const Color(0xFF10B981)),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // User Card & Logout
          if (user != null || isOffline)
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      user?.displayName ?? 'Offline User',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      user?.email ?? 'Local Cache',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                if (user?.photoUrl != null)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(user!.photoUrl!),
                  )
                else
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF6366F1),
                    child: Icon(Icons.person, color: Colors.white, size: 18),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    isOffline ? Icons.exit_to_app : Icons.logout,
                    color: const Color(0xFFEF4444),
                    size: 20,
                  ),
                  tooltip: isOffline ? 'Exit Offline Mode' : 'Logout',
                  onPressed: isOffline
                      ? () => ref.read(authProvider.notifier).exitOfflineMode()
                      : () => ref.read(authProvider.notifier).signOut(),
                ),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isActive = _editorTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _editorTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1) : const Color(0x1194A3B8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFF6366F1) : const Color(0x2294A3B8),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownToolbar() {
    final isOffline = ref.watch(authProvider).isOfflineMode;
    if (isOffline) return const SizedBox.shrink();

    final List<Map<String, dynamic>> items = [
      {'icon': Icons.title, 'tooltip': 'Heading 1', 'action': () => _insertMarkdown('# ')},
      {'icon': Icons.text_fields, 'tooltip': 'Heading 2', 'action': () => _insertMarkdown('## ')},
      {'icon': Icons.format_bold, 'tooltip': 'Bold', 'action': () => _insertMarkdown('**', suffix: '**')},
      {'icon': Icons.format_italic, 'tooltip': 'Italic', 'action': () => _insertMarkdown('*', suffix: '*')},
      {'icon': Icons.format_quote, 'tooltip': 'Blockquote', 'action': () => _insertMarkdown('> ')},
      {'icon': Icons.code, 'tooltip': 'Code Block', 'action': () => _insertMarkdown('```\n', suffix: '\n```')},
      {'icon': Icons.link, 'tooltip': 'Link', 'action': () => _insertMarkdown('[', suffix: '](url)')},
      {'icon': Icons.image, 'tooltip': 'Web Image', 'action': () => _insertMarkdown('![alt text](', suffix: ')')},
      {'icon': Icons.video_library, 'tooltip': 'Web Video', 'action': () => _insertMarkdown('@[video](', suffix: ')')},
      {'icon': Icons.play_circle_outline, 'tooltip': 'YouTube Video', 'action': () => _insertMarkdown('@[youtube](', suffix: ')')},
      {'icon': Icons.add_to_photos, 'tooltip': 'Drive Media', 'action': () => _showDriveMediaPicker(context)},
      {'icon': Icons.format_list_bulleted, 'tooltip': 'Bullet List', 'action': () => _insertMarkdown('- ')},
      {'icon': Icons.format_list_numbered, 'tooltip': 'Numbered List', 'action': () => _insertMarkdown('1. ')},
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1F94A3B8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            return IconButton(
              icon: Icon(item['icon'] as IconData, size: 18, color: const Color(0xFF94A3B8)),
              tooltip: item['tooltip'] as String,
              onPressed: item['action'] as VoidCallback,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFileEditor(BuildContext context, DriveState driveState) {
    final isEditing = _editingFileId != null;
    final isOffline = ref.watch(authProvider).isOfflineMode;
    final isLargeScreen = _wasLastBuildLargeScreen ?? false;

    // 1. Idle Placeholder State (No Document Selected & Not Creating)
    if (!isEditing && !_isCreatingNew) {
      return _buildIdlePlaceholder();
    }

    // 2. Loading State (If a document is selected but content is still downloading)
    final isReading = driveState.isLoading &&
        driveState.operationType == 'read' &&
        driveState.activeFileId == _editingFileId;

    if (isReading) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x1F334155),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: const Color(0x2294A3B8), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            Text(
              'Loading document contents...',
              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 16),
            ),
          ],
        ),
      );
    }

    // 3. Normal Editor/Viewer State
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0x1F334155),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x2294A3B8), width: 1),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Edit Document' : 'Create New Document',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearEditor,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Close'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildTabButton('Write', 0),
                const SizedBox(width: 8),
                _buildTabButton('Preview', 1),
                if (isLargeScreen) ...[
                  const SizedBox(width: 8),
                  _buildTabButton('Split View', 2),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (_editorTabIndex == 0) ...[
              if (!isEditing) _buildFolderBadge(driveState),
              _buildTitleField(isEditing, isOffline),
              const SizedBox(height: 16),
              _buildMarkdownToolbar(),
              _buildContentField(isOffline, maxLines: 12),
            ] else if (_editorTabIndex == 1) ...[
              _buildPreviewPane(context),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isEditing) _buildFolderBadge(driveState),
                        _buildTitleField(isEditing, isOffline),
                        const SizedBox(height: 16),
                        _buildMarkdownToolbar(),
                        _buildContentField(isOffline, maxLines: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Preview',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildPreviewPane(context),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (isOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x11EF4444),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x22EF4444)),
                ),
                child: Text(
                  'Creating and editing notes is disabled in offline guest mode. Log in with internet connection to modify notes.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFFCA5A5),
                  ),
                ),
              )
            else if (driveState.isLoading &&
                (driveState.operationType == 'create' || driveState.operationType == 'update'))
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              )
            else
              ElevatedButton(
                onPressed: _saveFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                child: Text(
                  isEditing ? 'Save Changes' : 'Save to Google Drive',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdlePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(32.0),
      height: 400,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x0C334155),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x1194A3B8), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0x1F6366F1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.edit_note,
              size: 48,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Document Selected',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select an existing document from the left list to edit or preview it, or create a brand new Markdown note.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _editingFileId = null;
                _isCreatingNew = true;
                _titleController.clear();
                _contentController.clear();
                _editorTabIndex = 0;
              });
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create New Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleField(bool isEditing, bool isOffline) {
    return TextFormField(
      controller: _titleController,
      enabled: !isEditing && !isOffline,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Document Title',
        labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        hintText: 'e.g. todo_list.md',
        hintStyle: GoogleFonts.inter(color: const Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0x3394A3B8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0x1194A3B8)),
        ),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Please enter a title';
        }
        return null;
      },
    );
  }

  Widget _buildContentField(bool isOffline, {required int maxLines}) {
    return TextFormField(
      controller: _contentController,
      focusNode: _contentFocusNode,
      maxLines: maxLines,
      enabled: !isOffline,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Content (Markdown)',
        labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        hintText: 'Type your secure note here...',
        hintStyle: GoogleFonts.inter(color: const Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0x3394A3B8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0x1194A3B8)),
        ),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Please enter some content';
        }
        return null;
      },
    );
  }

  Widget _buildPreviewPane(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300, maxHeight: 450),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3394A3B8)),
      ),
      child: SingleChildScrollView(
        child: MarkdownBody(
          data: _contentController.text.isEmpty
              ? '*Nothing to preview yet. Write something in the editor.*'
              : _contentController.text,
          selectable: true,
          styleSheet: _getMarkdownStyleSheet(context),
          extensionSet: md.ExtensionSet(
            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            [
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
              YoutubeSyntax(),
              WebVideoSyntax(),
              DriveVideoSyntax(),
            ],
          ),
          builders: {
            'youtube': YoutubeElementBuilder(),
            'video': VideoElementBuilder(ref),
            'img': DriveImageBuilder(ref),
          },
        ),
      ),
    );
  }

  Widget _buildFolderBadge(DriveState driveState) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 14, color: Color(0xFFF59E0B)),
          const SizedBox(width: 6),
          Text(
            'Target Folder: ${_getFolderName(_selectedFolderId, driveState)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_selectedFolderId != null && _selectedFolderId != driveState.rootFolderId) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFolderId = null;
                });
              },
              child: const Text(
                '(Reset to Root)',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6366F1),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getFolderName(String? folderId, DriveState driveState) {
    if (folderId == null || folderId == driveState.rootFolderId) {
      return 'Root Directory';
    }
    try {
      final folder = driveState.files.firstWhere((f) => f.id == folderId);
      return folder.name ?? 'Untitled Folder';
    } catch (_) {
      return 'Subfolder';
    }
  }

  void _onFileSelected(String fileId, String fileName, DriveState driveState) async {
    final isCached = driveState.fileContents.containsKey(fileId);
    
    String? parentId;
    try {
      final fileObj = driveState.files.firstWhere((f) => f.id == fileId);
      parentId = fileObj.parents?.first;
    } catch (_) {}

    setState(() {
      _editingFileId = fileId;
      _selectedFolderId = parentId;
      _isCreatingNew = false;
      _titleController.text = fileName;
      _contentController.text = driveState.fileContents[fileId] ?? '';
      _editorTabIndex = _wasLastBuildLargeScreen == true ? 2 : 0;
    });
    
    if (!isCached) {
      ref.read(driveProvider.notifier).readFile(fileId);
    }
  }

  Widget _buildFileExplorer(BuildContext context, DriveState driveState) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0x1F334155),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x2294A3B8), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Documents',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8), size: 20),
                tooltip: 'Refresh list',
                onPressed: () => ref.read(driveProvider.notifier).loadFiles(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // New Document and New Folder Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _editingFileId = null;
                      _isCreatingNew = true;
                      _titleController.clear();
                      _contentController.clear();
                      _editorTabIndex = 0; // Default to Write tab when creating
                    });
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Doc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateFolderDialog(context, parentFolderId: _selectedFolderId),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 14),
                  label: const Text('Folder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: driveState.files.isEmpty &&
                    driveState.isLoading &&
                    driveState.operationType == 'list'
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                    ),
                  )
                : driveState.files.isEmpty
                    ? _buildEmptyState()
                    : _buildFolderTreeList(driveState),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: const Color(0xFF475569),
          ),
          const SizedBox(height: 16),
          Text(
            'No files found',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first folder or document using the buttons above.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTreeList(DriveState driveState) {
    final rootId = driveState.rootFolderId;
    if (rootId == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
        ),
      );
    }

    final Map<String, List<drive.File>> childrenMap = {};
    for (final file in driveState.files) {
      final parents = file.parents ?? [];
      for (final p in parents) {
        childrenMap.putIfAbsent(p, () => []).add(file);
      }
    }

    final treeWidgets = _buildTreeNodes(rootId, driveState, childrenMap);

    if (treeWidgets.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      children: treeWidgets,
    );
  }

  List<Widget> _buildTreeNodes(
    String parentId,
    DriveState driveState,
    Map<String, List<drive.File>> childrenMap,
  ) {
    final items = childrenMap[parentId] ?? [];
    
    // Sort items: folders first (alphabetical), then files (alphabetical)
    items.sort((a, b) {
      final isFolderA = a.mimeType == 'application/vnd.google-apps.folder';
      final isFolderB = b.mimeType == 'application/vnd.google-apps.folder';
      if (isFolderA != isFolderB) {
        return isFolderA ? -1 : 1;
      }
      return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
    });

    List<Widget> nodes = [];
    for (final item in items) {
      final id = item.id ?? '';
      if (item.mimeType == 'application/vnd.google-apps.folder') {
        final isExpanded = _expandedFolderIds.contains(id);
        final isSelected = _selectedFolderId == id;
        
        nodes.add(
          _buildFolderTile(context, item, isExpanded, isSelected, driveState),
        );
        
        if (isExpanded) {
          nodes.add(
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0x1A94A3B8), width: 1.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Column(
                    children: _buildTreeNodes(id, driveState, childrenMap),
                  ),
                ),
              ),
            ),
          );
        }
      } else {
        final isSelected = _editingFileId == id;
        nodes.add(
          _buildFileTile(context, item, isSelected, driveState),
        );
      }
    }
    return nodes;
  }

  Widget _buildFolderTile(
    BuildContext context,
    drive.File folder,
    bool isExpanded,
    bool isSelected,
    DriveState driveState,
  ) {
    final folderId = folder.id ?? '';
    final folderName = folder.name ?? 'Untitled Folder';
    final isOffline = ref.watch(authProvider).isOfflineMode;

    final isProcessing = driveState.isLoading &&
        driveState.activeFileId == folderId &&
        (driveState.operationType == 'delete' || driveState.operationType == 'update');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x1F22D3EE) : Colors.transparent, // Cyan background tint when selected
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _selectedFolderId = folderId;
            if (_expandedFolderIds.contains(folderId)) {
              _expandedFolderIds.remove(folderId);
            } else {
              _expandedFolderIds.add(folderId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 16,
                color: const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.folder_open : Icons.folder,
                size: 18,
                color: const Color(0xFFF59E0B), // Amber color
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 14, color: Color(0xFF06B6D4)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'New Document inside folder',
                onPressed: () {
                  setState(() {
                    _selectedFolderId = folderId;
                    _editingFileId = null;
                    _isCreatingNew = true;
                    _titleController.clear();
                    _contentController.clear();
                    _editorTabIndex = 0;
                  });
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 14, color: Color(0xFFF59E0B)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'New Subfolder',
                onPressed: () => _showCreateFolderDialog(context, parentFolderId: folderId),
              ),
              const SizedBox(width: 8),
              if (isProcessing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined, size: 14, color: Color(0xFF38BDF8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Move folder',
                  onPressed: isOffline
                      ? null
                      : () => _showMoveFileDialog(context, folder, driveState),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete folder',
                  onPressed: isOffline
                      ? null
                      : () => _confirmDeleteFolder(context, folderId, folderName),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(
    BuildContext context,
    drive.File file,
    bool isSelected,
    DriveState driveState,
  ) {
    final fileId = file.id ?? '';
    final fileName = file.name ?? 'Untitled';
    final isOffline = ref.watch(authProvider).isOfflineMode;

    final isProcessing = driveState.isLoading &&
        driveState.activeFileId == fileId &&
        (driveState.operationType == 'delete' || driveState.operationType == 'update');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x336366F1) : Colors.transparent, // Indigo tint
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _onFileSelected(fileId, fileName, driveState),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            children: [
              const SizedBox(width: 20),
              const Icon(
                Icons.description_outlined,
                size: 16,
                color: Color(0xFF38BDF8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isProcessing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined, size: 14, color: Color(0xFF38BDF8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Move document',
                  onPressed: isOffline
                      ? null
                      : () => _showMoveFileDialog(context, file, driveState),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete document',
                  onPressed: isOffline
                      ? null
                      : () => _confirmDelete(context, fileId, fileName),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context, {String? parentFolderId}) {
    final TextEditingController folderNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Create Folder',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: folderNameController,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Folder Name',
            labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0x3394A3B8)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFFF59E0B)),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final name = folderNameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(dialogContext).pop();
                try {
                  await ref.read(driveProvider.notifier).createFolder(name, parentFolderId: parentFolderId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Folder "$name" created successfully!')),
                    );
                  }
                } catch (e) {
                  // Error handles automatically in driveProvider listener
                }
              }
            },
          ),
        ],
      ),
    );
  }

  String _getFolderDisplayPath(String folderId, DriveState driveState) {
    final rootFolderId = driveState.rootFolderId;
    if (rootFolderId == null || folderId == rootFolderId) {
      return 'Root';
    }
    try {
      final folder = driveState.files.firstWhere((f) => f.id == folderId);
      final parentId = folder.parents?.first;
      if (parentId == null || parentId == rootFolderId) {
        return folder.name ?? 'Untitled Folder';
      }
      return '${_getFolderDisplayPath(parentId, driveState)} > ${folder.name}';
    } catch (_) {
      return 'Unknown Folder';
    }
  }

  bool _isDescendant(String parentId, String childId, DriveState driveState) {
    if (parentId == childId) return true;
    try {
      final childFolder = driveState.files.firstWhere((f) => f.id == childId);
      final parents = childFolder.parents ?? [];
      for (final p in parents) {
        if (_isDescendant(parentId, p, driveState)) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  void _showMoveFileDialog(BuildContext context, drive.File file, DriveState driveState) {
    final fileId = file.id ?? '';
    final fileName = file.name ?? 'Untitled';
    final currentParentId = file.parents?.first ?? driveState.rootFolderId;

    // Filter all folders and sort them by path
    final folders = driveState.files
        .where((f) => f.mimeType == 'application/vnd.google-apps.folder')
        .toList();

    // Generate path and sort
    final Map<String, String> paths = {};
    for (final folder in folders) {
      if (folder.id != null) {
        paths[folder.id!] = _getFolderDisplayPath(folder.id!, driveState);
      }
    }

    final sortedFolders = folders.toList()
      ..sort((a, b) {
        final pathA = paths[a.id] ?? '';
        final pathB = paths[b.id] ?? '';
        return pathA.toLowerCase().compareTo(pathB.toLowerCase());
      });

    String? selectedFolderId = currentParentId;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'Move Document',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move "$fileName" to:',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x3394A3B8)),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Option for Root Directory
                        RadioListTile<String>(
                          title: Text(
                            'Root Directory (CloudSync Docs)',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: selectedFolderId == driveState.rootFolderId
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          value: driveState.rootFolderId ?? '',
                          groupValue: selectedFolderId,
                          activeColor: const Color(0xFF06B6D4),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedFolderId = val;
                            });
                          },
                        ),
                        const Divider(color: Color(0x1A94A3B8), height: 1),
                        // Options for all subfolders
                        ...sortedFolders.map((folder) {
                          final folderId = folder.id ?? '';
                          final path = paths[folderId] ?? folder.name ?? 'Untitled';
                          
                          // Prevent moving a folder into itself or its descendants
                          final isSelfOrDescendant = _isDescendant(fileId, folderId, driveState);
                          
                          return RadioListTile<String>(
                            title: Text(
                              path,
                              style: GoogleFonts.inter(
                                color: isSelfOrDescendant ? const Color(0xFF475569) : Colors.white,
                                fontSize: 13,
                                fontWeight: selectedFolderId == folderId
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: isSelfOrDescendant
                                ? Text(
                                    folderId == fileId
                                        ? 'Cannot move folder into itself'
                                        : 'Cannot move folder into its own subfolder',
                                    style: TextStyle(
                                      color: Colors.redAccent.withValues(alpha: 0.7),
                                      fontSize: 11,
                                    ),
                                  )
                                : null,
                            value: folderId,
                            groupValue: selectedFolderId,
                            activeColor: const Color(0xFF06B6D4),
                            onChanged: isSelfOrDescendant
                                ? null
                                : (val) {
                                    setDialogState(() {
                                      selectedFolderId = val;
                                    });
                                  },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(0x336366F1),
              ),
              onPressed: selectedFolderId == currentParentId || selectedFolderId == null
                  ? null
                  : () async {
                      Navigator.of(dialogContext).pop();
                      try {
                        await ref.read(driveProvider.notifier).moveFile(
                              fileId,
                              selectedFolderId!,
                              oldParentId: currentParentId,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Moved "$fileName" successfully!')),
                          );
                        }
                        if (_editingFileId == fileId) {
                          setState(() {
                            _selectedFolderId = selectedFolderId;
                          });
                        }
                      } catch (e) {
                        // Error handles in provider error listener
                      }
                    },
              child: const Text('Move', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String fileId, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Delete Document',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete "$fileName" from your Google Drive?',
          style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(driveProvider.notifier).deleteFile(fileId);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, String folderId, String folderName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Delete Folder',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete the folder "$folderName" and all its documents from your Google Drive?',
          style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete All', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(driveProvider.notifier).deleteFile(folderId);
              if (_selectedFolderId == folderId) {
                setState(() {
                  _selectedFolderId = null;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDriveMediaPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return _DriveMediaPickerDialog(
          selectedFolderId: _selectedFolderId,
          onInsert: (String tag) {
            _insertMarkdown(tag);
          },
        );
      },
    );
  }
}

class _DriveMediaPickerDialog extends ConsumerStatefulWidget {
  final String? selectedFolderId;
  final Function(String tag) onInsert;

  const _DriveMediaPickerDialog({
    required this.selectedFolderId,
    required this.onInsert,
  });

  @override
  ConsumerState<_DriveMediaPickerDialog> createState() => _DriveMediaPickerDialogState();
}

class _DriveMediaPickerDialogState extends ConsumerState<_DriveMediaPickerDialog> {
  bool _isUploading = false;
  String? _uploadStatus;

  String _formatSize(String? sizeStr) {
    if (sizeStr == null) return 'Unknown size';
    final bytes = int.tryParse(sizeStr);
    if (bytes == null) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleUpload() async {
    try {
      final picked = await pickMediaFile();
      if (picked == null) return;

      setState(() {
        _isUploading = true;
        _uploadStatus = 'Uploading ${picked.name}...';
      });

      final uploadedFile = await ref.read(driveProvider.notifier).uploadMedia(
        picked.name,
        picked.bytes,
        picked.mimeType,
        parentFolderId: widget.selectedFolderId,
      );

      if (uploadedFile != null && uploadedFile.id != null) {
        final fileId = uploadedFile.id!;
        final name = uploadedFile.name ?? 'media';
        final isVideo = picked.mimeType.startsWith('video/');

        final tag = isVideo
            ? '@[drive_video](drive://$fileId)'
            : '![$name](drive://$fileId)';

        widget.onInsert(tag);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('Successfully uploaded and inserted $name'),
            ),
          );
        }
      } else {
        throw Exception('File upload failed: No ID returned');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Upload failed: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driveState = ref.watch(driveProvider);

    // Filter files to only show images and videos
    final mediaFiles = driveState.files.where((file) {
      final mime = file.mimeType ?? '';
      return mime.startsWith('image/') || mime.startsWith('video/');
    }).toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Select Google Drive Media',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          if (!_isUploading)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.upload, size: 16, color: Colors.white),
              label: Text(
                'Upload',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              onPressed: _handleUpload,
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 360,
        child: _isUploading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _uploadStatus ?? 'Uploading media...',
                      style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              )
            : mediaFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.perm_media_outlined,
                          size: 48,
                          color: Color(0xFF475569),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No media files found in Drive',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Upload an image or video to get started',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF475569),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: mediaFiles.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0x1F94A3B8)),
                    itemBuilder: (context, index) {
                      final file = mediaFiles[index];
                      final isVideo = file.mimeType?.startsWith('video/') ?? false;
                      final isImage = file.mimeType?.startsWith('image/') ?? false;

                      IconData fileIcon = Icons.insert_drive_file;
                      Color iconColor = const Color(0xFF94A3B8);
                      if (isVideo) {
                        fileIcon = Icons.video_library;
                        iconColor = const Color(0xFF3B82F6);
                      } else if (isImage) {
                        fileIcon = Icons.image;
                        iconColor = const Color(0xFF10B981);
                      }

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(fileIcon, color: iconColor, size: 20),
                        ),
                        title: Text(
                          file.name ?? 'Unnamed file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatSize(file.size)} • ${file.mimeType}',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF475569),
                          size: 16,
                        ),
                        onTap: () {
                          final fileId = file.id!;
                          final name = file.name ?? 'media';
                          final tag = isVideo
                              ? '@[drive_video](drive://$fileId)'
                              : '![$name](drive://$fileId)';

                          widget.onInsert(tag);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
