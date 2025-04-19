import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logger/logger.dart';
import 'package:rtcapp2/data/chat_room_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../providers/room_provider.dart';
import '../services/auth_service.dart';
import 'chat_room_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Room? _room;
  final _logger = Logger(printer: LogfmtPrinter());
  bool _keyObscure = true;
  bool _secretObscure = true;
  String _selectedDuration = '1小时';
  final List<String> _durations = [
    '1小时',
    '6小时',
    '24小时',
    '168小时',
    '720小时',
    '8760小时'
  ];
  final Map<String, int> _durationHours = {
    '1小时': 1,
    '6小时': 6,
    '24小时': 24,
    '168小时': 168, // 7天
    '720小时': 720, // 30天
    '8760小时': 8760, // 1年
  };

  ColorScheme _colorScheme() {
    return Theme.of(context).colorScheme;
  }

  Widget _buildUsernameField() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '用户名',
                    hintText: '输入用户名',
                    prefixIcon: const Icon(Icons.person, color: Colors.blue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    filled: true,
                    fillColor: Colors.blue.shade50,
                    errorText:
                        _usernameController.text.isEmpty ? '请输入用户名' : null,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      onPressed: () {
                        _usernameController.text =
                            (List.from(AppConstants.RANDOM_NAMES)..shuffle())
                                .first;
                        ref.read(homeScreenProvider.notifier).updateState();
                      },
                    ),
                  ),
                  onChanged: (_) =>
                      ref.read(homeScreenProvider.notifier).updateState(),
                  validator: (value) => value!.isEmpty ? '请输入用户名' : null,
                ),
              ),
              // Removed IconButton from here
              // IconButton(
              //   icon: const Icon(Icons.refresh, color: Colors.blue),
              //   onPressed: () {
              //     _usernameController.text =
              //         (List.from(AppConstants.RANDOM_NAMES)..shuffle()).first;
              //     ref.read(homeScreenProvider.notifier).updateState();
              //   },
              // ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 监听homeScreenProvider以响应状态变化
    final homeScreenState = ref.watch(homeScreenProvider);
    if (homeScreenState.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '加入会议',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontFamily: 'Comic Sans MS'),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.surface,
        elevation: 4,
        shadowColor: colorScheme.onPrimaryContainer,
      ),
      backgroundColor: Colors.pink.shade50,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildUrlField(),
                  const SizedBox(height: 16),
                  _buildKeyField(),
                  const SizedBox(height: 16),
                  _buildSecretField(),
                  const SizedBox(height: 16),
                  _buildRoomField(),
                  const SizedBox(height: 16),
                  _buildDurationField(),
                  const SizedBox(height: 16),
                  _buildUsernameField(),
                  const SizedBox(height: 32),
                  _buildJoinButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.yellow.shade100,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.pinkAccent.withOpacity(0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.videocam_rounded,
              size: 60,
              color: Colors.pinkAccent,
            ),
            const Positioned(
              right: 10,
              bottom: 10,
              child: Icon(Icons.favorite, color: Colors.redAccent, size: 24),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '加入视频会议',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.pinkAccent.shade400,
            fontFamily: 'Comic Sans MS',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '输入会议信息以加入或创建会议',
          style: TextStyle(
            color: Colors.purple.shade300,
            fontFamily: 'Comic Sans MS',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildUrlField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _urlController,
      keyboardType: TextInputType.url,
      style: TextStyle(
        fontFamily: 'Comic Sans MS',
        // 根据背景色动态调整文字颜色
        color: colorScheme.brightness == Brightness.light
            ? Colors.black87 // 浅色模式用深色文字
            : colorScheme.onSurface, // 深色模式用默认主题色
      ),
      decoration: InputDecoration(
        labelText: '会议 URL',
        labelStyle: TextStyle(
          color: colorScheme.brightness == Brightness.light
              ? Colors.black54
              : colorScheme.onSurface.withOpacity(0.8),
        ),
        hintText: 'ws://your.livekit.server',
        hintStyle: TextStyle(
          color: colorScheme.brightness == Brightness.light
              ? Colors.black38
              : colorScheme.onSurface.withOpacity(0.6),
        ),
        prefixIcon: const Icon(Icons.link_rounded, color: Colors.purple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        // 动态调整填充色透明度
        fillColor: colorScheme.brightness == Brightness.light
            ? Colors.yellow.shade50.withOpacity(0.7) // 浅色模式降低黄色饱和度
            : Colors.yellow.shade50,
        // 深色模式保持原样
        errorStyle: TextStyle(
          color: colorScheme.error, // 错误文字使用系统错误色
        ),
        errorText: _validateUrl(),
      ),
      onChanged: (_) => ref.read(homeScreenProvider.notifier).updateState(),
      validator: (value) => _validateUrl(),
    );
  }

  String? _validateUrl() {
    final value = _urlController.text;
    if (value.isEmpty) return '请输入URL';
    if (!value.startsWith('ws://') && !value.startsWith('wss://')) {
      return 'URL必须以 ws:// 或 wss:// 开头';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute) return 'URL格式不正确';
    return null;
  }

  Widget _buildKeyField() {
    return TextFormField(
      controller: _keyController,
      obscureText: _keyObscure,
      decoration: InputDecoration(
        labelText: 'API Key',
        hintText: '输入 API Key',
        prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.orange),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: Colors.pink.shade50,
        errorText: _keyController.text.isEmpty ? '请输入API Key' : null,
        suffixIcon: IconButton(
          icon: Icon(_keyObscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.pinkAccent),
          onPressed: () {
            _keyObscure = !_keyObscure;
            ref.read(homeScreenProvider.notifier).updateState();
          },
        ),
      ),
      onChanged: (_) => ref.read(homeScreenProvider.notifier).updateState(),
      validator: (value) => value!.isEmpty ? '请输入API Key' : null,
    );
  }

  Widget _buildSecretField() {
    return TextFormField(
      controller: _secretController,
      obscureText: _secretObscure,
      decoration: InputDecoration(
        labelText: 'API Secret',
        hintText: '输入 API Secret',
        prefixIcon: const Icon(Icons.lock_rounded, color: Colors.purple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: Colors.purple.shade50,
        errorText: _secretController.text.isEmpty ? '请输入API Secret' : null,
        suffixIcon: IconButton(
          icon: Icon(_secretObscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.purple),
          onPressed: () {
            _secretObscure = !_secretObscure;
            ref.read(homeScreenProvider.notifier).updateState();
          },
        ),
      ),
      onChanged: (_) => {ref.read(homeScreenProvider.notifier).updateState()},
      validator: (value) => value!.isEmpty ? '请输入API Secret' : null,
    );
  }

  Widget _buildRoomField() {
    return TextFormField(
      controller: _roomController,
      decoration: InputDecoration(
        labelText: '房间名',
        hintText: '输入房间名',
        prefixIcon: const Icon(Icons.meeting_room_rounded, color: Colors.green),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: Colors.green.shade50,
        errorText: _roomController.text.isEmpty ? '请输入房间名' : null,
      ),
      onChanged: (_) => ref.read(homeScreenProvider.notifier).updateState(),
      validator: (value) => value!.isEmpty ? '请输入房间名' : null,
    );
  }

  Widget _buildDurationField() {
    return DropdownButtonFormField<String>(
      value: _selectedDuration,
      decoration: InputDecoration(
        labelText: 'Token 有效时间',
        prefixIcon: const Icon(Icons.timer_rounded, color: Colors.purple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: Colors.purple.shade50,
      ),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.purple),
      style: TextStyle(
        color: Colors.purple.shade700,
        fontFamily: 'Comic Sans MS',
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          _selectedDuration = newValue;
          ref.read(homeScreenProvider.notifier).updateState();
          _saveInputs();
        }
      },
      items: _durations.map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
    );
  }

  Widget _buildJoinButton() {
    final isValid = _validateUrl() == null &&
        _keyController.text.isNotEmpty &&
        _secretController.text.isNotEmpty &&
        _roomController.text.isNotEmpty;
    return FilledButton(
      onPressed: isValid ? _joinRoom : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color.fromARGB(255, 240, 128, 236),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.pink.shade100.withOpacity(0.6),
        disabledForegroundColor: Colors.purple.shade200.withOpacity(0.6),
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 6,
        shadowColor: Colors.pinkAccent.withOpacity(0.3),
      ),
      child: const Text(
        '加入会议',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Comic Sans MS',
        ),
      ),
    );
  }

  Future<void> _joinRoom() async {
    if (!mounted) return;
    final isValid = _validateUrl() == null &&
        _keyController.text.isNotEmpty &&
        _secretController.text.isNotEmpty &&
        _usernameController.text.isNotEmpty &&
        _roomController.text.isNotEmpty;
    _logger.v("joinRoom");
    if (isValid) {
      try {
        ref.read(homeScreenProvider.notifier).setLoading(true);
        final hours = _durationHours[_selectedDuration] ?? 1;
        final username = _usernameController.text.trim();

        final token = AuthService.generateVideoToken(
          _roomController.text.trim(),
          username,
          Duration(hours: hours),
          _keyController.text.trim(),
          _secretController.text.trim(),
        );
        _logger.d("尝试连接，userName:$username,duration:${hours}h,token:$token");
        _logger.v("尝试生成token");
        final result = await ref.read(roomProvider.notifier).connectToRoom(
              _urlController.text.trim(),
              token,
            );
        result.fold(
            onSuccess: (room) {
              ref.read(chatRoomStateProvider.notifier).setState(ChatRoomState(
                  url: _urlController.text.trim(),
                  token: token,
                  isConnected: true));
              _logger.i("连接房间成功");
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('连接房间成功'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
                final router = Navigator.of(context);
                Future.delayed(
                    const Duration(seconds: 2),
                    () => router.push(
                          MaterialPageRoute(
                            builder: (context) => const ChatRoomScreen(),
                          ),
                        ));
              }
            },
            onFailure: (e) => {
                  if (mounted)
                    {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('连接失败: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      )
                    }
                });
      } finally {
        ref.read(homeScreenProvider.notifier).setLoading(false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedInputs();
    _urlController.addListener(_saveInputs);
    _keyController.addListener(_saveInputs);
    _secretController.addListener(_saveInputs);
    _roomController.addListener(_saveInputs);
    _usernameController.addListener(_saveInputs);
  }

  Future<void> _loadSavedInputs() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text =
        prefs.getString('meeting_url') ?? 'ws://localhost:7880';
    _keyController.text = prefs.getString('api_key') ?? 'devkey';
    _secretController.text = prefs.getString('api_secret') ?? 'secret';
    _roomController.text = prefs.getString('room_name') ?? 'test_room';
    _selectedDuration = prefs.getString('duration') ?? '1小时';
    _usernameController.text = prefs.getString('nickname') ?? '';

    // 通知Riverpod状态更新
    ref.read(homeScreenProvider.notifier).updateState();
  }

  Future<void> _saveInputs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('meeting_url', _urlController.text);
    await prefs.setString('api_key', _keyController.text);
    await prefs.setString('api_secret', _secretController.text);
    await prefs.setString('room_name', _roomController.text);
    await prefs.setString('duration', _selectedDuration);
    await prefs.setString('nickname', _usernameController.text);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _secretController.dispose();
    _roomController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}

// 添加相关的Riverpod Provider
final homeScreenProvider =
    StateNotifierProvider<HomeScreenNotifier, HomeScreenState>((ref) {
  return HomeScreenNotifier();
});

class HomeScreenState {
  final bool isLoading;

  HomeScreenState({
    this.isLoading = false,
  });

  HomeScreenState copyWith({
    bool? isLoading,
  }) {
    return HomeScreenState(
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Notifier类
class HomeScreenNotifier extends StateNotifier<HomeScreenState> {
  HomeScreenNotifier() : super(HomeScreenState());

  void updateState() {
    state = state.copyWith();
  }

  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }
}
