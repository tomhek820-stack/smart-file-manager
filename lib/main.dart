import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const SmartFileManagerApp());

class SmartFileManagerApp extends StatelessWidget {
  const SmartFileManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدير الملفات الذكي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF00897B)),
      home: const FileAccessScreen(),
    );
  }
}

class FileAccessScreen extends StatefulWidget {
  const FileAccessScreen({super.key});
  @override
  State<FileAccessScreen> createState() => _FileAccessScreenState();
}

class _FileAccessScreenState extends State<FileAccessScreen> {
  List<FileSystemEntity> _files = [];
  String _status = 'اضغط الزر لطلب الصلاحيات وعرض الملفات';
  String _currentPath = '';

  Future<void> _requestPermissions() async {
    var storage = await Permission.storage.request();
    setState(() => _status = 'حالة التخزين: ${storage.name}');

    if (await Permission.manageExternalStorage.isDenied) {
      final manage = await Permission.manageExternalStorage.request();
      setState(() => _status = 'حالة الوصول الكامل: ${manage.name}');
      if (manage.isPermanentlyDenied) {
        await openAppSettings();
        return;
      }
    }
    await [Permission.photos, Permission.videos, Permission.audio].request();
    await _loadFiles();
  }

  Future<void> _loadFiles() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0');
      if (!await dir.exists()) {
        dir = (await getExternalStorageDirectory())!;
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    try {
      final list = await dir.list().toList();
      list.sort((a, b) {
        final aDir = a is Directory, bDir = b is Directory;
        if (aDir && !bDir) return -1;
        if (!aDir && bDir) return 1;
        return a.path.compareTo(b.path);
      });
      setState(() {
        _files = list;
        _currentPath = dir.path;
        _status = 'تم تحميل ${list.length} عنصرًا من ${dir.path}';
      });
    } catch (e) {
      setState(() => _status = 'خطأ في القراءة: $e');
    }
  }

  IconData _iconFor(FileSystemEntity f) {
    if (f is Directory) return Icons.folder;
    final ext = f.path.split('.').last.toLowerCase();
    if (['jpg','jpeg','png','gif','webp','bmp'].contains(ext)) return Icons.image_outlined;
    if (['mp4','mkv','avi','mov','webm'].contains(ext)) return Icons.videocam_outlined;
    if (['mp3','wav','ogg','m4a','flac'].contains(ext)) return Icons.audiotrack_outlined;
    if (['pdf','doc','docx','txt','xlsx','pptx'].contains(ext)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدير الملفات الذكي'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Column(
              children: [
                Text(_status, textAlign: TextAlign.center),
                if (_currentPath.isNotEmpty)
                  Text(_currentPath, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _requestPermissions,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('طلب الصلاحيات وعرض الملفات'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? const Center(child: Text('لا توجد ملفات بعد'))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (_, i) {
                      final f = _files[i];
                      final name = f.path.split('/').last;
                      return ListTile(
                        leading: Icon(_iconFor(f)),
                        title: Text(name.isEmpty ? f.path : name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(f.path, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
