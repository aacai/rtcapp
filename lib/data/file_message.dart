import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/file_service.dart';

/// 文件消息类，用于在聊天室中显示和处理文件传输
class FileMessage {
  final String senderId;
  final String senderName;
  final bool isLocal;
  final DateTime timestamp;
  final FileInfo fileInfo;
  final FileTransferStatus status;
  final double progress;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final String? transferRate;

  FileMessage({
    required this.senderId,
    required this.senderName,
    required this.isLocal,
    required this.timestamp,
    required this.fileInfo,
    this.status = FileTransferStatus.pending,
    this.progress = 0.0,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onOpen,
    this.onDownload,
    this.transferRate,
  });

  FileMessage copyWith({
    String? senderId,
    String? senderName,
    bool? isLocal,
    DateTime? timestamp,
    FileInfo? fileInfo,
    FileTransferStatus? status,
    double? progress,
    VoidCallback? onAccept,
    VoidCallback? onReject,
    VoidCallback? onCancel,
    VoidCallback? onOpen,
    VoidCallback? onDownload,
    String? transferRate,
  }) {
    return FileMessage(
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      isLocal: isLocal ?? this.isLocal,
      timestamp: timestamp ?? this.timestamp,
      fileInfo: fileInfo ?? this.fileInfo,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      onAccept: onAccept ?? this.onAccept,
      onReject: onReject ?? this.onReject,
      onCancel: onCancel ?? this.onCancel,
      onOpen: onOpen ?? this.onOpen,
      onDownload: onDownload ?? this.onDownload,
    );
  }

  /// 创建文件消息的JSON表示
  Map<String, dynamic> toJson() {
    return {
      'type': 'file',
      'fileId': fileInfo.fileId,
      'fileName': fileInfo.fileName,
      'fileType': fileInfo.fileType,
      'fileSize': fileInfo.fileSize,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// 从JSON创建文件消息
  static FileMessage? fromJson(Map<String, dynamic> json,
      {bool isLocal = false}) {
    try {
      return FileMessage(
        senderId: json['senderId'] ?? '',
        senderName: json['senderName'] ?? '未知用户',
        isLocal: isLocal,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
        fileInfo: FileInfo(
          fileId: json['fileId'] ?? '',
          fileName: json['fileName'] ?? '未知文件',
          fileType: json['fileType'] ?? '未知',
          fileSize: json['fileSize'] ?? 0,
          senderId: json['senderId'] ?? '',
          senderName: json['senderName'] ?? '未知用户',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
        ),
      );
    } catch (e) {
      debugPrint('解析文件消息错误: $e');
      return null;
    }
  }

  /// 创建文件请求消息
  static String createFileRequestMessage(FileInfo fileInfo, String senderName) {
    final Map<String, dynamic> message = {
      'type': 'file_request',
      'fileId': fileInfo.fileId,
      'fileName': fileInfo.fileName,
      'fileType': fileInfo.fileType,
      'fileSize': fileInfo.fileSize,
      'senderId': fileInfo.senderId,
      'senderName': senderName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return 'FILE_MSG|${Uri.encodeFull(message.toString())}';
  }

  /// 创建文件响应消息
  static String createFileResponseMessage(
      String fileId, bool accepted, String receiverId, String receiverName) {
    final Map<String, dynamic> message = {
      'type': 'file_response',
      'fileId': fileId,
      'accepted': accepted,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return 'FILE_MSG|${Uri.encodeFull(message.toString())}';
  }

  /// 解析文件消息
  static Map<String, dynamic>? parseFileMessage(String message) {
    try {
      if (message.startsWith('FILE_MSG|')) {
        final jsonStr = Uri.decodeFull(message.substring(9));
        // 将字符串转换为Map
        final Map<String, dynamic> data = {};
        final parts = jsonStr.substring(1, jsonStr.length - 1).split(', ');

        for (var part in parts) {
          final keyValue = part.split(': ');
          if (keyValue.length == 2) {
            String key = keyValue[0].trim();
            // 移除键的引号
            if (key.startsWith("'") && key.endsWith("'")) {
              key = key.substring(1, key.length - 1);
            }

            String value = keyValue[1].trim();
            // 处理值
            if (value == 'true') {
              data[key] = true;
            } else if (value == 'false') {
              data[key] = false;
            } else if (int.tryParse(value) != null) {
              data[key] = int.parse(value);
            } else {
              // 移除值的引号
              if (value.startsWith("'") && value.endsWith("'")) {
                value = value.substring(1, value.length - 1);
              }
              data[key] = value;
            }
          }
        }

        return data;
      }
      return null;
    } catch (e) {
      debugPrint('解析文件消息错误: $e');
      return null;
    }
  }
}

/// 文件操作类，提供打开文件和共享文件功能
class FileOperations {
  /// 打开文件
  static Future<void> openFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      debugPrint('文件路径为空');
      return;
    }

    try {
      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        debugPrint('无法打开文件: $filePath');
      }
    } catch (e) {
      debugPrint('打开文件错误: $e');
    }
  }

  /// 分享文件
  static Future<void> shareFile(String? filePath, String fileName) async {
    if (filePath == null || filePath.isEmpty) {
      debugPrint('文件路径为空');
      return;
    }

    try {
      await Share.shareXFiles([XFile(filePath)], text: '分享文件: $fileName');
    } catch (e) {
      debugPrint('分享文件错误: $e');
    }
  }

  /// 复制文件到下载目录
  static Future<String?> copyToDownloads(
      String? filePath, String fileName) async {
    if (filePath == null || filePath.isEmpty) {
      debugPrint('文件路径为空');
      return null;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('文件不存在');
        return null;
      }

      // 获取下载目录
      Directory? downloadsDir;
      try {
        if (Platform.isAndroid) {
          // Android 平台使用外部存储的 Download 目录
          downloadsDir = Directory('/storage/emulated/0/Download');
          if (!await downloadsDir.exists()) {
            // 如果目录不存在，尝试创建
            await downloadsDir.create(recursive: true);
          }
        } else if (Platform.isIOS) {
          // iOS 平台使用 Documents 目录
          final documentsDir = await getApplicationDocumentsDirectory();
          downloadsDir = Directory('${documentsDir.path}/Downloads');
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
        }
      } catch (e) {
        debugPrint('获取下载目录失败: $e');
        // 使用应用文档目录作为备选
        final appDir = await getApplicationDocumentsDirectory();
        downloadsDir = appDir;
      }

      if (downloadsDir == null) {
        debugPrint('无法获取下载目录');
        return null;
      }

      // 确保文件名唯一
      String targetPath = '${downloadsDir.path}/$fileName';
      final fileExt =
          fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final fileNameWithoutExt = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;

      int counter = 1;
      while (await File(targetPath).exists()) {
        targetPath =
            '${downloadsDir.path}/$fileNameWithoutExt($counter)$fileExt';
        counter++;
      }

      // 复制文件
      await file.copy(targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('复制文件到下载目录错误: $e');
      return null;
    }
  }
}

/// 文件消息UI组件
class FileMessageWidget extends StatelessWidget {
  final FileMessage fileMessage;

  const FileMessageWidget({Key? key, required this.fileMessage})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isLocal = fileMessage.isLocal;
    final fileInfo = fileMessage.fileInfo;
    final status = fileMessage.status;
    final progress = fileMessage.progress;
    final bool canOpen =
        status == FileTransferStatus.completed && fileInfo.localPath != null;

    // 构建文件操作菜单
    void _showOptions(BuildContext context) {
      if (status != FileTransferStatus.completed &&
          status != FileTransferStatus.pending) {
        return; // 仅在文件传输完成或等待状态时显示选项
      }

      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: Text(fileInfo.fileName),
          message: Text('文件大小: ${fileInfo.readableSize}'),
          actions: <CupertinoActionSheetAction>[
            if (canOpen)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  FileOperations.openFile(fileInfo.localPath);
                },
                child: const Text('打开'),
              ),
            if (status == FileTransferStatus.completed)
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(context);
                  if (fileInfo.localPath != null) {
                    final savePath = await FileOperations.copyToDownloads(
                        fileInfo.localPath, fileInfo.fileName);
                    if (savePath != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('文件已保存到: $savePath')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存文件失败')),
                      );
                    }
                  } else if (fileMessage.onDownload != null) {
                    fileMessage.onDownload!();
                  }
                },
                child: const Text('下载/保存'),
              ),
            if (canOpen)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  FileOperations.shareFile(
                      fileInfo.localPath, fileInfo.fileName);
                },
                child: const Text('分享'),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                // 复制文件名
                final text = '${fileInfo.fileName} (${fileInfo.readableSize})';
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制文件信息到剪贴板')),
                );
              },
              child: const Text('复制信息'),
            ),
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
      onTap: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLocal ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isLocal ? Colors.blue.shade300 : Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getFileIcon(fileInfo.fileType),
                  color: isLocal ? Colors.blue.shade700 : Colors.grey.shade700,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileInfo.fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        fileInfo.readableSize,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (status == FileTransferStatus.pending && !isLocal)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: fileMessage.onReject,
                    child: const Text('拒绝'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: fileMessage.onAccept,
                    child: const Text('接收'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),
                ],
              )
            else if (status == FileTransferStatus.pending && isLocal)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '等待对方接收...',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: fileMessage.onCancel,
                    child: const Text('取消'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              )
            else if (status == FileTransferStatus.transferring)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                          if (fileMessage.transferRate != null)
                            Text(
                              fileMessage.transferRate!,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                      if (isLocal)
                        TextButton(
                          onPressed: fileMessage.onCancel,
                          child: const Text('取消'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ],
              )
            else if (status == FileTransferStatus.completed)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '传输完成',
                    style:
                        TextStyle(color: Colors.green.shade700, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  if (canOpen)
                    TextButton(
                      onPressed: () {
                        FileOperations.openFile(fileInfo.localPath);
                      },
                      child: const Text('打开'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              )
            else if (status == FileTransferStatus.failed)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '传输失败',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                ],
              )
            else if (status == FileTransferStatus.canceled)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '已取消',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileType) {
    fileType = fileType.toLowerCase();

    if (fileType.contains('pdf')) {
      return Icons.picture_as_pdf;
    } else if (fileType.contains('doc') || fileType.contains('word')) {
      return Icons.description;
    } else if (fileType.contains('xls') ||
        fileType.contains('excel') ||
        fileType.contains('sheet')) {
      return Icons.table_chart;
    } else if (fileType.contains('ppt') || fileType.contains('presentation')) {
      return Icons.slideshow;
    } else if (fileType.contains('jpg') ||
        fileType.contains('jpeg') ||
        fileType.contains('png') ||
        fileType.contains('gif') ||
        fileType.contains('bmp') ||
        fileType.contains('webp') ||
        fileType.contains('image')) {
      return Icons.image;
    } else if (fileType.contains('mp3') ||
        fileType.contains('wav') ||
        fileType.contains('ogg') ||
        fileType.contains('audio')) {
      return Icons.audio_file;
    } else if (fileType.contains('mp4') ||
        fileType.contains('avi') ||
        fileType.contains('mov') ||
        fileType.contains('wmv') ||
        fileType.contains('video')) {
      return Icons.video_file;
    } else if (fileType.contains('zip') ||
        fileType.contains('rar') ||
        fileType.contains('7z') ||
        fileType.contains('tar') ||
        fileType.contains('gz')) {
      return Icons.folder_zip;
    } else if (fileType.contains('txt') || fileType.contains('text')) {
      return Icons.text_snippet;
    } else if (fileType.contains('html') ||
        fileType.contains('xml') ||
        fileType.contains('json') ||
        fileType.contains('css') ||
        fileType.contains('js')) {
      return Icons.code;
    } else {
      return Icons.insert_drive_file;
    }
  }
}
