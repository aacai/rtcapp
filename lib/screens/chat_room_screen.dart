import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'; // 确保导入WebRTC相关包
import 'package:rtcapp2/providers/room_provider.dart';
import '../data/chat_message.dart';
import '../data/file_message.dart';
import '../services/file_service.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  Room? room;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<FileMessage> _fileMessages = [];
  bool _isStreaming = false;
  bool _isFrontCamera = true;
  StreamSubscription? _dataSubscription;
  final FileService _fileService = FileService();

  // 文件传输相关
  Map<String, List<FileChunk>> _receivingFiles = {};
  Map<String, FileInfo> _pendingFiles = {};
  bool _isSelectingFile = false;

  @override
  void initState() {
    super.initState();
    // 使用延迟确保构建完成后设置监听器
    Future.delayed(Duration.zero, () {
      _setupRoomListeners();
    });
  }

  void _setupRoomListeners() {
    final room = ref.read(roomProvider);
    if (room != null) {
      // 监听数据消息
      _dataSubscription = room.events.listen((event) {
        if (event is DataReceivedEvent) {
          _handleDataReceived(event);
        }
      })();
    }
  }

  void _handleDataReceived(DataReceivedEvent event) {
    try {
      final data = Uint8List.fromList(event.data);
      if (data.isEmpty) {
        debugPrint('接收到空数据');
        return;
      }

      // 尝试解析为字符串
      final String message = String.fromCharCodes(data);

      // 检查是否是文件消息
      if (message.startsWith('FILE_MSG|')) {
        _handleFileMessage(message);
        return;
      }

      // 检查是否是文件块
      if (data.length > 20) {
        try {
          final fileChunk = FileChunk.fromBytes(data);
          if (fileChunk != null) {
            _handleFileChunk(
                fileChunk,
                event.participant?.identity ??
                    event.participant?.name ??
                    '匿名者');
            return;
          }
        } catch (e) {
          debugPrint('解析文件块错误: $e');
        }
      }

      // 处理普通文本消息
      try {
        final decoded = message.split('|'); // 格式: "senderName|message"
        if (decoded.length >= 2) {
          setState(() {
            _messages.add(ChatMessage(
              sender: decoded[0].trim(),
              message: decoded[1].trim(),
              isLocal: false,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        } else {
          debugPrint('消息格式不正确: $message');
        }
      } catch (e) {
        debugPrint('解析文本消息错误: $e');
      }
    } catch (e) {
      debugPrint('处理接收数据错误: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('处理消息时出错')),
      );
    }
  }

  // 处理文件消息
  void _handleFileMessage(String message) {
    final data = FileMessage.parseFileMessage(message);
    if (data == null) return;

    final type = data['type'];

    if (type == 'file_request') {
      // 收到文件传输请求
      final fileId = data['fileId'];
      final fileName = data['fileName'];
      final fileType = data['fileType'];
      final fileSize = data['fileSize'];
      final senderId = data['senderId'];
      final senderName = data['senderName'];

      final fileInfo = FileInfo(
        fileName: fileName,
        fileType: fileType,
        fileSize: fileSize,
        senderId: senderId,
        senderName: senderName,
        fileId: fileId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
      );

      // 添加到待处理文件列表
      _pendingFiles[fileId] = fileInfo;

      // 创建文件消息并显示
      setState(() {
        _fileMessages.add(FileMessage(
          senderId: senderId,
          senderName: senderName,
          isLocal: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
          fileInfo: fileInfo,
          onAccept: () => _acceptFile(fileId),
          onReject: () => _rejectFile(fileId),
        ));
      });
      _scrollToBottom();
    } else if (type == 'file_response') {
      // 收到文件传输响应
      final fileId = data['fileId'];
      final accepted = data['accepted'];
      final receiverId = data['receiverId'];
      final receiverName = data['receiverName'];

      if (accepted) {
        // 对方接受了文件，开始传输
        _startFileTransfer(fileId, receiverId);
      } else {
        // 对方拒绝了文件
        setState(() {
          for (int i = 0; i < _fileMessages.length; i++) {
            if (_fileMessages[i].fileInfo.fileId == fileId) {
              _fileMessages[i] = _fileMessages[i].copyWith(
                status: FileTransferStatus.canceled,
              );
              break;
            }
          }
        });
      }
    }
  }

  // 处理文件块
  void _handleFileChunk(FileChunk chunk, String senderId) {
    final fileId = chunk.fileId;
    debugPrint(
        '收到文件块，文件ID: $fileId, 块序号: ${chunk.chunkIndex}/${chunk.totalChunks}');

    // 如果是新文件，初始化接收列表
    if (!_receivingFiles.containsKey(fileId)) {
      debugPrint('初始化新文件接收，文件ID: $fileId');
      _receivingFiles[fileId] = [];

      // 更新UI显示传输中
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.transferring,
              progress: 0.0,
            );
            break;
          }
        }
      });
    }

    // 添加块到接收列表
    _receivingFiles[fileId]!.add(chunk);

    // 计算进度
    final progress = _receivingFiles[fileId]!.length / chunk.totalChunks;

    // 更新UI显示进度
    setState(() {
      for (int i = 0; i < _fileMessages.length; i++) {
        if (_fileMessages[i].fileInfo.fileId == fileId) {
          _fileMessages[i] = _fileMessages[i].copyWith(
            progress: progress,
          );
          break;
        }
      }
    });

    // 检查是否接收完成
    if (_receivingFiles[fileId]!.length == chunk.totalChunks) {
      _completeFileTransfer(fileId);
    }
  }

  // 接受文件
  void _acceptFile(String fileId) {
    final fileInfo = _pendingFiles[fileId];
    if (fileInfo == null) return;

    final localParticipant = room?.localParticipant;
    if (localParticipant == null) return;

    // 发送接受响应
    final response = FileMessage.createFileResponseMessage(
      fileId,
      true,
      localParticipant.identity,
      localParticipant.name ?? '我',
    );

    try {
      localParticipant.publishData(
        response.codeUnits,
        reliable: true,
      );

      // 更新UI状态为等待传输
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.pending,
              onAccept: null,
              onReject: null,
            );
            break;
          }
        }
      });
    } catch (e) {
      debugPrint('发送文件接受响应失败: $e');
    }
  }

  // 拒绝文件
  void _rejectFile(String fileId) {
    final fileInfo = _pendingFiles[fileId];
    if (fileInfo == null) return;

    final localParticipant = room?.localParticipant;
    if (localParticipant == null) return;

    // 发送拒绝响应
    final response = FileMessage.createFileResponseMessage(
      fileId,
      false,
      localParticipant.identity,
      localParticipant.name ?? '我',
    );

    try {
      localParticipant.publishData(
        response.codeUnits,
        reliable: true,
      );

      // 更新UI状态为已拒绝
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.canceled,
              onAccept: null,
              onReject: null,
            );
            break;
          }
        }
      });

      // 从待处理列表中移除
      _pendingFiles.remove(fileId);
    } catch (e) {
      debugPrint('发送文件拒绝响应失败: $e');
    }
  }

  // 开始文件传输
  Future<void> _startFileTransfer(String fileId, String receiverId) async {
    debugPrint('开始文件传输，文件ID: $fileId');
    final fileInfo = _pendingFiles[fileId];
    if (fileInfo == null) {
      debugPrint('错误：找不到文件信息，文件ID: $fileId');
      return;
    }

    final localParticipant = room?.localParticipant;
    if (localParticipant == null) {
      debugPrint('错误：未连接到房间');
      return;
    }

    const timeoutDuration = Duration(minutes: 30);

    // 更新UI状态为传输中
    setState(() {
      for (int i = 0; i < _fileMessages.length; i++) {
        if (_fileMessages[i].fileInfo.fileId == fileId) {
          _fileMessages[i] = _fileMessages[i].copyWith(
            status: FileTransferStatus.transferring,
            progress: 0.0,
            transferRate: '0 KB/s',
            onAccept: null,
            onReject: null,
          );
          break;
        }
      }
    });

    DateTime? lastUpdateTime;
    int transferredBytes = 0;

    try {
      debugPrint(
          '开始分割文件为块，文件名: ${fileInfo.fileName}, 大小: ${fileInfo.fileSize} bytes');
      // 分割文件为块
      final chunks = await _fileService.splitFileIntoChunks(fileInfo);
      if (chunks.isEmpty) {
        debugPrint('错误：文件分割失败，文件名: ${fileInfo.fileName}');
        throw Exception('文件分割失败');
      }
      debugPrint('文件分割成功，共 ${chunks.length} 个块');

      // 逐块发送
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        try {
          await localParticipant
              .publishData(
            chunk.toBytes(),
            reliable: true,
          )
              .timeout(timeoutDuration, onTimeout: () {
            debugPrint('文件块传输超时，文件ID: $fileId, 块序号: $i');
            throw TimeoutException('文件块传输超时');
          });
        } on TimeoutException catch (e) {
          debugPrint('文件块传输超时错误: $e');
          // 更新UI状态为失败
          setState(() {
            for (int j = 0; j < _fileMessages.length; j++) {
              if (_fileMessages[j].fileInfo.fileId == fileId) {
                _fileMessages[j] = _fileMessages[j].copyWith(
                  status: FileTransferStatus.failed,
                );
                break;
              }
            }
          });
          return;
        }
        debugPrint('发送文件块 $i，大小: ${chunk.data.length} bytes');
        // 更新进度和速率
        final progress = (i + 1) / chunks.length;
        transferredBytes += chunk.data.length;
        final now = DateTime.now();

        if (lastUpdateTime != null) {
          final elapsed = now.difference(lastUpdateTime!).inMilliseconds;
          if (elapsed > 500) {
            // 每500ms更新一次速率
            final rate = transferredBytes / elapsed * 1000; // bytes per second
            final rateText = rate > 1024
                ? '${(rate / 1024).toStringAsFixed(1)} KB/s'
                : '${rate.toStringAsFixed(1)} B/s';

            setState(() {
              for (int j = 0; j < _fileMessages.length; j++) {
                if (_fileMessages[j].fileInfo.fileId == fileId) {
                  _fileMessages[j] = _fileMessages[j].copyWith(
                    progress: progress,
                    transferRate: rateText,
                  );
                  break;
                }
              }
            });

            transferredBytes = 0;
            lastUpdateTime = now;
          }
        } else {
          lastUpdateTime = now;
        }

        // 增加等待时间到200ms，减少拥塞
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 更新UI状态为已完成
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.completed,
            );
            break;
          }
        }
      });

      // 从待处理列表中移除
      _pendingFiles.remove(fileId);
    } catch (e) {
      debugPrint('发送文件失败: $e');
      debugPrint('堆栈跟踪: ${e.toString()}');

      // 更新UI状态为失败
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.failed,
            );
            break;
          }
        }
      });
    }
  }

  // 完成文件传输
  Future<void> _completeFileTransfer(String fileId) async {
    debugPrint('开始合并文件块，文件ID: $fileId');
    try {
      final chunks = _receivingFiles[fileId];
      if (chunks == null || chunks.isEmpty) {
        debugPrint('错误：没有可合并的文件块，文件ID: $fileId');
        return;
      }

      // 合并文件块
      final fileData = _fileService.mergeFileChunks(chunks);

      // 获取文件信息
      FileInfo? fileInfo;
      for (int i = 0; i < _fileMessages.length; i++) {
        if (_fileMessages[i].fileInfo.fileId == fileId) {
          fileInfo = _fileMessages[i].fileInfo;
          break;
        }
      }

      if (fileInfo == null) return;

      // 保存文件
      final filePath = await _fileService.saveReceivedFile(
        fileInfo.fileName,
        fileData,
      );

      // 更新UI状态为已完成
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            // 添加打开和下载功能
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.completed,
              fileInfo: fileInfo!.copyWith(localPath: filePath),
              onOpen: filePath != null
                  ? () => FileOperations.openFile(filePath)
                  : null,
              onDownload: filePath != null
                  ? () async {
                      final savePath = await FileOperations.copyToDownloads(
                        filePath,
                        fileInfo!.fileName,
                      );
                      if (savePath != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('文件已保存到: $savePath')),
                        );
                      }
                    }
                  : null,
            );
            break;
          }
        }
      });

      // 清理资源
      _receivingFiles.remove(fileId);
      _pendingFiles.remove(fileId);

      // 显示保存成功提示
      if (filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('文件已保存到: $filePath'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '确定',
            onPressed: () {},
          ),
        ));
      }
    } catch (e) {
      debugPrint('保存接收的文件失败: $e');
      debugPrint('堆栈跟踪: ${e.toString()}');

      // 更新UI状态为失败
      setState(() {
        for (int i = 0; i < _fileMessages.length; i++) {
          if (_fileMessages[i].fileInfo.fileId == fileId) {
            _fileMessages[i] = _fileMessages[i].copyWith(
              status: FileTransferStatus.failed,
            );
            break;
          }
        }
      });
    }
  }

  // 选择并发送文件
  Future<void> _pickAndSendFile() async {
    if (_isSelectingFile) return;

    setState(() {
      _isSelectingFile = true;
    });

    try {
      final localParticipant = room?.localParticipant;
      if (localParticipant == null) throw Exception('未连接到房间');

      // 选择文件
      final fileInfo = await _fileService.pickFile();
      if (fileInfo == null) return; // 用户取消选择

      // 设置发送者信息
      final updatedFileInfo = fileInfo.copyWith(
        senderId: localParticipant.identity,
        senderName: localParticipant.name ?? '我',
      );

      // 添加到待处理文件列表
      _pendingFiles[updatedFileInfo.fileId] = updatedFileInfo;

      // 创建文件消息并显示
      setState(() {
        _fileMessages.add(FileMessage(
          senderId: localParticipant.identity,
          senderName: localParticipant.name ?? '我',
          isLocal: true,
          timestamp: DateTime.now(),
          fileInfo: updatedFileInfo,
          status: FileTransferStatus.transferring,
          progress: 0.0,
          onCancel: () => _cancelFileTransfer(updatedFileInfo.fileId),
          // 支持自己发送的文件也可以下载/打开
          onOpen: updatedFileInfo.localPath != null
              ? () => FileOperations.openFile(updatedFileInfo.localPath)
              : null,
          onDownload: updatedFileInfo.localPath != null
              ? () async {
                  final savePath = await FileOperations.copyToDownloads(
                    updatedFileInfo.localPath,
                    updatedFileInfo.fileName,
                  );
                  if (savePath != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('文件已保存到: $savePath')),
                    );
                  }
                }
              : null,
        ));
      });
      _scrollToBottom();

      // 直接开始文件传输
      await _startFileTransfer(updatedFileInfo.fileId, '');
    } catch (e) {
      debugPrint('选择文件错误: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('选择文件失败: ${e.toString()}'),
        backgroundColor: Colors.red,
      ));
    } finally {
      setState(() {
        _isSelectingFile = false;
      });
    }
  }

  // 取消文件传输
  void _cancelFileTransfer(String fileId) {
    // 更新UI状态为已取消
    setState(() {
      for (int i = 0; i < _fileMessages.length; i++) {
        if (_fileMessages[i].fileInfo.fileId == fileId) {
          _fileMessages[i] = _fileMessages[i].copyWith(
            status: FileTransferStatus.canceled,
            onCancel: null,
          );
          break;
        }
      }
    });

    // 从待处理列表中移除
    _pendingFiles.remove(fileId);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final message = _messageController.text.trim();
    final localParticipant = room?.localParticipant;

    if (localParticipant != null && room != null) {
      // 发送消息到房间
      final data = '${localParticipant.name ?? "我"}|$message';
      try {
        localParticipant.publishData(
          data.codeUnits,
          reliable: true,
        );

        // 添加到本地消息列表
        setState(() {
          _messages.add(ChatMessage(
            sender: localParticipant.name ?? '我',
            message: message,
            isLocal: true,
            timestamp: DateTime.now(),
          ));
        });

        _messageController.clear();
        _scrollToBottom();
      } catch (e) {
        debugPrint('发送消息失败: $e');
      }
    }
  }

  Future<void> _toggleCamera() async {
    final localParticipant = room?.localParticipant;
    if (localParticipant == null) return;

    setState(() {
      _isStreaming = !_isStreaming;
    });

    if (_isStreaming) {
      // 开始推流
      try {
        final options = CameraCaptureOptions(
          cameraPosition:
              _isFrontCamera ? CameraPosition.front : CameraPosition.back,
          params: const VideoParameters(
            dimensions: VideoDimensions(640, 480),
          ),
        );

        final cameraTrack = await LocalVideoTrack.createCameraTrack(options);
        await localParticipant.publishVideoTrack(cameraTrack);
      } catch (e) {
        debugPrint('开启摄像头失败: $e');
        setState(() {
          _isStreaming = false;
        });
      }
    } else {
      // 停止推流
      try {
        for (final pub in localParticipant.videoTrackPublications) {
          if (pub.source == TrackSource.camera) {
            await localParticipant.unpublishAllTracks();
          }
        }
      } catch (e) {
        debugPrint('停止推流失败: $e');
      }
    }
  }

  Future<void> _toggleCameraFacing() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });

    // 如果正在推流，重新启动摄像头
    if (_isStreaming) {
      final localParticipant = room?.localParticipant;
      if (localParticipant == null) return;

      // 先停止当前推流
      try {
        for (final pub in localParticipant.videoTrackPublications) {
          if (pub.source == TrackSource.camera) {
            await localParticipant.unpublishAllTracks();
          }
        }

        // 短暂延迟后重新开启摄像头
        await Future.delayed(const Duration(milliseconds: 300));

        // 使用新的摄像头方向开启
        final options = CameraCaptureOptions(
          cameraPosition:
              _isFrontCamera ? CameraPosition.front : CameraPosition.back,
          params: const VideoParameters(
            dimensions: VideoDimensions(640, 480),
          ),
        );

        final cameraTrack = await LocalVideoTrack.createCameraTrack(options);
        await localParticipant.publishVideoTrack(cameraTrack);
      } catch (e) {
        debugPrint('切换摄像头失败: $e');
        setState(() {
          _isStreaming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatRoomStateProvider);
    room = ref.read(roomProvider);

    // 获取房间人数
    final participantCount = room?.remoteParticipants.length ?? 0;
    // 加上本地用户
    final totalCount =
        participantCount + (room?.localParticipant != null ? 1 : 0);

    // 检查是否有人在推流视频
    var videoPubs = 0;
    final videoPubss = room?.remoteParticipants.values;
    if (videoPubss != null) {
      for (var pub in videoPubss) {
        pub.videoTrackPublications.forEach((element) {
          if (element.track?.isActive == true) {
            videoPubs++;
          }
        });
      }
    }

    // 如果本地用户也在推流，加上本地用户
    if (_isStreaming) {
      videoPubs++;
    }

    final hasVideoStreams = videoPubs > 0;

    // 合并消息列表，按时间排序
    final allMessages = [..._messages, ..._fileMessages];
    allMessages.sort((a, b) {
      if (a is ChatMessage && b is ChatMessage) {
        return a.timestamp.compareTo(b.timestamp);
      } else if (a is FileMessage && b is FileMessage) {
        return a.timestamp.compareTo(b.timestamp);
      } else if (a is ChatMessage && b is FileMessage) {
        return a.timestamp.compareTo(b.timestamp);
      } else if (a is FileMessage && b is ChatMessage) {
        return a.timestamp.compareTo(b.timestamp);
      }
      return 0;
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () async {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('确认退出'),
                content: const Text('确定要离开聊天室吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child:
                        const Text('确定', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (shouldExit ?? false) Navigator.pop(context);
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('聊天室'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalCount人',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          // 摄像头推流按钮
          IconButton(
            icon: Icon(
              _isStreaming ? Icons.videocam : Icons.videocam_off,
              color: _isStreaming ? Colors.blue : null,
            ),
            onPressed: _toggleCamera,
          ),
          // 翻转摄像头按钮
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: _toggleCameraFacing,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // 群设置菜单
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 推流通知横幅
          if (hasVideoStreams)
            InkWell(
              onTap: () {
                // 打开视频预览
                _showVideoPreview(context);
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.blue.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '$videoPubs人正在视频通话中',
                      style: const TextStyle(color: Colors.blue),
                    ),
                    const Spacer(),
                    const Text(
                      '点击查看',
                      style: TextStyle(color: Colors.blue),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Colors.blue, size: 18),
                  ],
                ),
              ),
            ),
          // 聊天消息列表
          Expanded(
            child: _messages.isEmpty && _fileMessages.isEmpty
                ? const Center(
                    child: Text('暂无消息，开始聊天吧'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length + _fileMessages.length,
                    itemBuilder: (context, index) {
                      // 合并普通消息和文件消息，按时间排序
                      final allMessages = [..._messages, ..._fileMessages];
                      allMessages.sort((a, b) {
                        DateTime timeA;
                        DateTime timeB;

                        if (a is ChatMessage) {
                          timeA = a.timestamp;
                        } else {
                          timeA = (a as FileMessage).timestamp;
                        }

                        if (b is ChatMessage) {
                          timeB = b.timestamp;
                        } else {
                          timeB = (b as FileMessage).timestamp;
                        }

                        return timeA.compareTo(timeB);
                      });

                      final message = allMessages[index];

                      if (message is ChatMessage) {
                        return _buildChatBubble(message);
                      } else {
                        return _buildFileMessageBubble(message as FileMessage);
                      }
                    },
                  ),
          ),
          // 输入框和发送按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : Colors.grey.shade800,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              children: [
                // 文件选择按钮
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.attach_file,
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.blue.shade700
                            : Colors.blue.shade300,
                        size: 22,
                      ),
                      onPressed: _isSelectingFile ? null : _pickAndSendFile,
                      tooltip: '发送文件',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
                    ),
                    const SizedBox(width: 8),
                    if (_isSelectingFile)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.blue.shade50.withOpacity(0.5)
                                  : Colors.blueGrey.shade700.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                    ? Colors.blue.shade200
                                    : Colors.blueGrey.shade600,
                            width: 1.0,
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: '输入消息...',
                            hintStyle: TextStyle(
                              color: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.blue.shade300
                                  : Colors.blueGrey.shade300,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                    ? Colors.black87
                                    : Colors.white,
                          ),
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final isLocal = message.isLocal;

    // 显示消息选项菜单
    void _showMessageOptions(BuildContext context) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: const Text('消息选项'),
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.message));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制消息文本')),
                );
              },
              child: const Text('复制'),
            ),
            // 可以添加更多操作，如删除、转发等
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showMessageOptions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isLocal ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isLocal) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey,
                child: Text(
                  message.sender.isNotEmpty
                      ? message.sender.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isLocal)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        message.sender,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isLocal ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message.message,
                      style: TextStyle(
                        color: isLocal ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
            if (isLocal) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue,
                child: Text(
                  message.sender.isNotEmpty
                      ? message.sender.substring(0, 1).toUpperCase()
                      : '我',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(time.year, time.month, time.day);

    String prefix = '';
    if (messageDate == today) {
      prefix = '今天 ';
    } else if (messageDate == yesterday) {
      prefix = '昨天 ';
    } else {
      prefix = '${time.month}-${time.day} ';
    }

    return '$prefix${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // 构建文件消息气泡
  Widget _buildFileMessageBubble(FileMessage message) {
    final isLocal = message.isLocal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isLocal ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLocal) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey,
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isLocal)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.senderName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                FileMessageWidget(fileMessage: message),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          if (isLocal) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName.substring(0, 1).toUpperCase()
                    : '我',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showVideoPreview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 顶部把手指示器
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '视频通话',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildVideoGrid(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 20.0, horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      _isStreaming ? Icons.videocam_off : Icons.videocam,
                      _isStreaming ? '关闭视频' : '加入视频',
                      color: _isStreaming ? Colors.red : Colors.blue,
                      onTap: () {
                        _toggleCamera();
                        Navigator.pop(context);
                      },
                    ),
                    _buildActionButton(
                      _isFrontCamera
                          ? Icons.flip_camera_android
                          : Icons.flip_camera_ios,
                      '切换摄像头',
                      color: Colors.green,
                      onTap: () {
                        _toggleCameraFacing();
                      },
                    ),
                    _buildActionButton(
                      Icons.mic,
                      '加入语音',
                      color: Colors.amber,
                      onTap: () {
                        // 加入语音逻辑
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoGrid() {
    // 收集活跃的视频轨道和对应的参与者
    List<VideoTrack> videoTracks = [];
    List<String> participantNames = [];
    List<bool> isLocalFlags = [];

    // 检查远程参与者的视频
    if (room != null) {
      // 收集远程参与者的视频轨道
      for (final participant in room!.remoteParticipants.values) {
        for (final publication in participant.videoTrackPublications) {
          final track = publication.track;
          if (track != null && track.isActive && track is VideoTrack) {
            videoTracks.add(track);
            participantNames.add(participant.name ?? '未知用户');
            isLocalFlags.add(false);
          }
        }
      }

      // 检查本地用户的视频轨道
      if (_isStreaming && room!.localParticipant != null) {
        for (final publication
            in room!.localParticipant!.videoTrackPublications) {
          final track = publication.track;
          if (track != null && track.isActive && track is VideoTrack) {
            videoTracks.add(track);
            participantNames.add(room!.localParticipant!.name ?? '我');
            isLocalFlags.add(true);
          }
        }
      }
    }

    if (videoTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.grey[400],
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无视频画面',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮开启视频',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // 确定网格布局
    int crossAxisCount = 1;
    if (videoTracks.length > 1) {
      crossAxisCount = videoTracks.length <= 4 ? 2 : 3;
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 3 / 4, // 更适合移动设备的竖屏比例
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: videoTracks.length,
        itemBuilder: (context, index) {
          final videoTrack = videoTracks[index];
          final participantName = participantNames[index];
          final isLocal = isLocalFlags[index];

          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
              border: Border.all(
                color:
                    isLocal ? Colors.blue.withOpacity(0.6) : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 视频背景
                  Container(color: Colors.black),

                  // 视频画面
                  VideoTrackRenderer(
                    videoTrack,
                    fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),

                  // 底部渐变蒙版
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 70,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 参与者名称和指示器
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // 名称标签
                          Expanded(
                            child: Text(
                              participantName + (isLocal ? ' (我)' : ''),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                      color: Colors.black,
                                      blurRadius: 4,
                                      offset: Offset(0, 1))
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // 状态指示器
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 右上角本地/远程指示
                  if (isLocal)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '我的画面',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label,
      {required VoidCallback onTap, required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void deactivate() {
    ref.read(roomProvider.notifier).dispose();
    ref.read(chatRoomStateProvider.notifier).dispose();
    super.deactivate();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _dataSubscription?.cancel();
    super.dispose();
  }
}
