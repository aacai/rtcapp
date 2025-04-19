import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cross_file/cross_file.dart';
import 'package:mime/mime.dart';

/// 文件传输状态
enum FileTransferStatus {
  /// 等待中
  pending,

  /// 传输中
  transferring,

  /// 已完成
  completed,

  /// 已取消
  canceled,

  /// 失败
  failed,
}

/// 文件信息模型
class FileInfo {
  final String fileName;
  final String fileType;
  final int fileSize;
  final String? localPath;
  final String senderId;
  final String senderName;
  final String fileId;
  final DateTime timestamp;
  final FileTransferStatus status;
  final double progress;
  final Uint8List? bytes; // 用于Web平台存储文件数据

  FileInfo({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    this.localPath,
    required this.senderId,
    required this.senderName,
    required this.fileId,
    required this.timestamp,
    this.status = FileTransferStatus.pending,
    this.progress = 0.0,
    this.bytes,
  });

  FileInfo copyWith({
    String? fileName,
    String? fileType,
    int? fileSize,
    String? localPath,
    String? senderId,
    String? senderName,
    String? fileId,
    DateTime? timestamp,
    FileTransferStatus? status,
    double? progress,
    Uint8List? bytes,
  }) {
    return FileInfo(
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      localPath: localPath ?? this.localPath,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      fileId: fileId ?? this.fileId,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytes: bytes ?? this.bytes,
    );
  }

  /// 获取文件大小的可读字符串
  String get readableSize {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = fileSize.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }
}

/// 文件块信息
class FileChunk {
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;

  FileChunk({
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
  });

  /// 将文件块转换为字节数组
  Uint8List toBytes() {
    // 格式: fileId|chunkIndex|totalChunks|data
    final header = '$fileId|$chunkIndex|$totalChunks|';
    final headerBytes = Uint8List.fromList(header.codeUnits);
    final result = Uint8List(headerBytes.length + data.length);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, result.length, data);
    return result;
  }

  /// 从字节数组解析文件块
  static FileChunk? fromBytes(Uint8List bytes) {
    try {
      final String rawData = String.fromCharCodes(bytes);
      final headerEndIndex = rawData.indexOf(
              '|', rawData.indexOf('|', rawData.indexOf('|') + 1) + 1) +
          1;
      final header = rawData.substring(0, headerEndIndex);
      final parts = header.split('|');

      if (parts.length < 3) return null;

      final fileId = parts[0];
      final chunkIndex = int.parse(parts[1]);
      final totalChunks = int.parse(parts[2]);

      final data = bytes.sublist(headerEndIndex);

      return FileChunk(
        fileId: fileId,
        chunkIndex: chunkIndex,
        totalChunks: totalChunks,
        data: data,
      );
    } catch (e) {
      debugPrint('解析文件块错误: $e');
      return null;
    }
  }
}

/// 文件服务类，处理文件选择和保存的平台差异
class FileService {
  // 单例模式
  static final FileService _instance = FileService._internal();
  factory FileService() => _instance;
  FileService._internal();

  // 文件块大小 (64KB)
  static const int chunkSize = 64 * 1024;

  /// 选择文件
  /// 返回选择的文件信息，如果用户取消则返回null
  Future<FileInfo?> pickFile() async {
    try {
      // 检查权限 - 针对不同平台请求不同权限
      if (!kIsWeb) {
        if (Platform.isAndroid) {
          // Android 13+ (SDK 33+) 需要特定的权限
          final sdkVersion = await _getAndroidSdkVersion();
          if (sdkVersion >= 33) {
            // 请求照片和视频权限
            final photos = await Permission.photos.request();
            final videos = await Permission.videos.request();
            // 请求外部存储权限
            final storage = await Permission.manageExternalStorage.request();

            if (!photos.isGranted && !videos.isGranted && !storage.isGranted) {
              debugPrint('存储权限被拒绝');
              return null;
            }
          } else {
            // 旧版Android使用存储权限
            final status = await Permission.storage.request();
            if (!status.isGranted) {
              debugPrint('存储权限被拒绝');
              return null;
            }
          }
        } else if (Platform.isIOS) {
          // iOS需要照片库权限
          final status = await Permission.photos.request();
          if (!status.isGranted) {
            debugPrint('照片库权限被拒绝');
            return null;
          }
        }
      }

      // 使用FilePicker选择文件 - 针对不同平台设置不同选项
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        // 在iOS上使用原生文件选择器
        allowCompression: !kIsWeb && Platform.isIOS,
        // 在Android上使用媒体存储
        withData: kIsWeb || Platform.isIOS, // Web和iOS需要直接获取数据
      );

      if (result == null || result.files.isEmpty) {
        return null; // 用户取消选择
      }

      final file = result.files.first;
      final fileId = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      // 获取文件类型
      String fileType = file.extension ?? '';
      if (fileType.isEmpty && file.path != null) {
        // 尝试从MIME类型获取
        final mimeType = lookupMimeType(file.path!);
        if (mimeType != null) {
          final parts = mimeType.split('/');
          if (parts.length > 1) {
            fileType = parts[1];
          }
        }
      }
      if (fileType.isEmpty) {
        fileType = '未知';
      }

      return FileInfo(
        fileName: file.name,
        fileType: fileType,
        fileSize: file.size,
        localPath: file.path,
        senderId: '', // 发送时设置
        senderName: '', // 发送时设置
        fileId: fileId,
        timestamp: DateTime.now(),
        // 如果是Web平台，保存文件数据
        bytes: kIsWeb ? file.bytes : null,
      );
    } catch (e) {
      debugPrint('选择文件错误: $e');
      return null;
    }
  }

  /// 获取Android SDK版本
  Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      return int.parse(await _getSystemProperty('ro.build.version.sdk')) ?? 0;
    } catch (e) {
      debugPrint('获取Android SDK版本失败: $e');
      return 0;
    }
  }

  /// 获取Android系统属性
  Future<String> _getSystemProperty(String name) async {
    try {
      if (Platform.isAndroid) {
        // 这里需要使用平台通道或插件获取系统属性
        // 简化处理，返回一个默认值
        return '33'; // 默认返回Android 13
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /// 将文件分割成块
  Future<List<FileChunk>> splitFileIntoChunks(FileInfo fileInfo) async {
    try {
      final List<FileChunk> chunks = [];
      Uint8List bytes;

      // 根据平台获取文件数据
      if (kIsWeb) {
        // Web平台直接使用bytes
        if (fileInfo.bytes == null) {
          throw Exception('Web平台文件数据为空');
        }
        bytes = fileInfo.bytes!;
      } else if (fileInfo.localPath == null) {
        throw Exception('文件路径为空');
      } else {
        // 移动平台从文件路径读取
        final file = File(fileInfo.localPath!);
        bytes = await file.readAsBytes();
      }

      // 根据文件大小动态调整块大小
      int dynamicChunkSize = chunkSize;
      if (bytes.length > 10 * 1024 * 1024) {
        // 大于10MB的文件
        dynamicChunkSize = 128 * 1024; // 使用更大的块
      } else if (bytes.length < 1 * 1024 * 1024) {
        // 小于1MB的文件
        dynamicChunkSize = 32 * 1024; // 使用更小的块
      }

      final totalChunks = (bytes.length / dynamicChunkSize).ceil();

      for (var i = 0; i < totalChunks; i++) {
        final start = i * dynamicChunkSize;
        final end = (i + 1) * dynamicChunkSize > bytes.length
            ? bytes.length
            : (i + 1) * dynamicChunkSize;

        final chunkData = bytes.sublist(start, end);
        chunks.add(FileChunk(
          fileId: fileInfo.fileId,
          chunkIndex: i,
          totalChunks: totalChunks,
          data: chunkData,
        ));

        // 每创建10个块暂停一下，避免内存压力
        if (i % 10 == 0 && i > 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      return chunks;
    } catch (e) {
      debugPrint('分割文件错误: $e');
      return [];
    }
  }

  /// 保存接收到的文件
  Future<String?> saveReceivedFile(String fileName, Uint8List fileData) async {
    try {
      if (kIsWeb) {
        // Web平台使用浏览器下载
        return await _saveFileForWeb(fileName, fileData);
      }

      Directory? directory;
      String? filePath;

      if (Platform.isAndroid) {
        // 检查Android版本和权限
        final sdkVersion = await _getAndroidSdkVersion();
        if (sdkVersion >= 29) {
          // Android 10+
          // 使用媒体存储API或下载管理器
          try {
            // 首先尝试下载目录
            directory = Directory('/storage/emulated/0/Download');
            if (!await directory.exists()) {
              // 回退到应用专用外部存储
              final dirs = await getExternalStorageDirectories();
              if (dirs != null && dirs.isNotEmpty) {
                directory = dirs.first;
              } else {
                directory = await getExternalStorageDirectory();
              }
            }
          } catch (e) {
            // 如果无法访问下载目录，使用应用专用目录
            directory = await getApplicationDocumentsDirectory();
          }
        } else {
          // Android 9及以下可以直接使用下载目录
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        }
      } else if (Platform.isIOS) {
        // iOS平台保存到文档目录
        directory = await getApplicationDocumentsDirectory();
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // 桌面平台使用文档目录
        directory = await getApplicationDocumentsDirectory();
      } else {
        // 其他平台保存到临时目录
        directory = await getTemporaryDirectory();
      }

      if (directory == null) {
        throw Exception('无法获取存储目录');
      }

      // 确保目录存在
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 处理文件名冲突
      filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      if (await file.exists()) {
        // 如果文件已存在，添加时间戳
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final lastDot = fileName.lastIndexOf('.');
        if (lastDot > 0) {
          final name = fileName.substring(0, lastDot);
          final ext = fileName.substring(lastDot);
          filePath = '${directory.path}/${name}_$timestamp$ext';
        } else {
          filePath = '${directory.path}/${fileName}_$timestamp';
        }
      }

      // 写入文件
      await File(filePath).writeAsBytes(fileData);
      return filePath;
    } catch (e) {
      debugPrint('保存文件错误: $e');
      return null;
    }
  }

  /// Web平台保存文件
  Future<String?> _saveFileForWeb(String fileName, Uint8List fileData) async {
    try {
      // Web平台使用XFile创建下载链接
      final xFile = XFile.fromData(
        fileData,
        name: fileName,
        mimeType: lookupMimeType(fileName) ?? 'application/octet-stream',
      );

      // 在Web平台上，我们只能触发下载，无法获取保存路径
      // 返回文件名作为标识
      await xFile.saveTo('unused');
      return fileName;
    } catch (e) {
      debugPrint('Web平台保存文件错误: $e');
      return null;
    }
  }

  /// 合并文件块
  Uint8List mergeFileChunks(List<FileChunk> chunks) {
    // 按块索引排序
    chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    // 计算总大小
    int totalSize = 0;
    for (var chunk in chunks) {
      totalSize += chunk.data.length;
    }

    // 合并数据
    final result = Uint8List(totalSize);
    int offset = 0;

    for (var chunk in chunks) {
      result.setRange(offset, offset + chunk.data.length, chunk.data);
      offset += chunk.data.length;
    }

    return result;
  }
}
