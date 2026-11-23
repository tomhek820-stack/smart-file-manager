import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

void main() => runApp(const SmartFileManagerApp());

class SmartFileManagerApp extends StatelessWidget {
  const SmartFileManagerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF00897B)),
      home: const FileBrowser(),
    );
  }
}

class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key});
  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  List<FileSystemEntity> _all = [];
  List<FileSystemEntity> _visible = [];
  Directory? _current;
  final List<Directory> _history = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _type = 'الكل';
  String _sort = 'الاسم';
  bool _hasPerm = false;
  String _status = 'جارٍ التحقق من الصلاحيات...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPerms());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPerms() async {
    await Permission.storage.request();
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    await [Permission.photos, Permission.videos, Permission.audio].request();
    final granted = await Permission.storage.isGranted ||
        await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() {
      _hasPerm = granted;
      _status = granted ? 'الصلاحية ممنوحة' : 'الصلاحية مرفوضة';
    });
    if (granted) {
      await _openNoHistory(Directory('/storage/emulated/0'));
    }
  }

  Future<void> _openNoHistory(Directory dir) async {
    try {
      final list = await dir.list().toList();
      if (!mounted) return;
      setState(() {
        _current = dir;
        _all = list;
        _status = '${dir.path} — ${list.length} عنصر';
      });
      _apply();
    } catch (e) {
      if (mounted) setState(() => _status = 'خطأ: $e');
    }
  }

  Future<void> _open(Directory dir) async {
    if (_current != null) _history.add(_current!);
    await _openNoHistory(dir);
  }

  void _back() {
    if (_history.isEmpty) return;
    final dir = _history.removeLast();
    _openNoHistory(dir);
  }

  String _extOf(String path) {
    final name = path.split('/').last;
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  bool _isImage(String p) => ['jpg','jpeg','png','gif','webp','bmp','heic','svg'].contains(_extOf(p));
  bool _isVideo(String p) => ['mp4','mkv','avi','mov','webm','3gp','flv'].contains(_extOf(p));
  bool _isAudio(String p) => ['mp3','wav','ogg','m4a','flac','aac','opus'].contains(_extOf(p));
  bool _isDoc(String p) => ['pdf','doc','docx','txt','xlsx','xls','pptx','ppt','md','csv'].contains(_extOf(p));
  bool _isArchive(String p) => ['zip','rar','7z','tar','gz'].contains(_extOf(p));

  IconData _iconFor(FileSystemEntity f) {
    if (f is Directory) return Icons.folder;
    if (_isImage(f.path)) return Icons.image_outlined;
    if (_isVideo(f.path)) return Icons.videocam_outlined;
    if (_isAudio(f.path)) return Icons.audiotrack_outlined;
    if (_isDoc(f.path)) return Icons.description_outlined;
    if (_isArchive(f.path)) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes ب';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} غ.ب';
  }

  Map<String, dynamic> _smartParse(String text) {
    final t = text.toLowerCase();
    String? type;
    if (t.contains('صور') || t.contains('صورة')) type = 'image';
    if (t.contains('فيديو')) type = 'video';
    if (t.contains('صوت') || t.contains('أغنية') || t.contains('اغنية') || t.contains('موسيقى')) type = 'audio';
    if (t.contains('مستند') || t.contains('تقرير') || t.contains('pdf') || t.contains('وثيقة')) type = 'document';
    if (t.contains('مضغوط') || t.contains('zip') || t.contains('rar')) type = 'archive';

    final now = DateTime.now();
    DateTime? after;
    if (t.contains('اليوم')) after = DateTime(now.year, now.month, now.day);
    if (t.contains('الأسبوع') || t.contains('اسبوع')) after = now.subtract(const Duration(days: 7));
    if (t.contains('الشهر') || t.contains('شهر')) after = now.subtract(const Duration(days: 30));
    if (t.contains('السنة') || t.contains('سنة')) after = now.subtract(const Duration(days: 365));

    const stop = {'ابحث','عن','ملفات','ملف','التي','في','من','صور','صورة',
                  'فيديو','صوت','مستند','اليوم','الأسبوع','اسبوع','الشهر','شهر','السنة','سنة','pdf'};
    final words = text.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !stop.contains(w)).toList();
    return {'type': type, 'after': after, 'words': words};
  }

  void _apply() {
    var list = [..._all];

    if (_query.isNotEmpty) {
      final p = _smartParse(_query);
      if (p['type'] != null) {
        final t = p['type'];
        list = list.where((f) {
          if (f is Directory) return false;
          if (t == 'image') return _isImage(f.path);
          if (t == 'video') return _isVideo(f.path);
          if (t == 'audio') return _isAudio(f.path);
          if (t == 'document') return _isDoc(f.path);
          if (t == 'archive') return _isArchive(f.path);
          return true;
        }).toList();
      }
      if (p['after'] != null) {
        final after = p['after'] as DateTime;
        list = list.where((f) {
          try { return f.statSync().modified.isAfter(after); } catch (_) { return false; }
        }).toList();
      }
      final words = (p['words'] as List).cast<String>();
      if (words.isNotEmpty) {
        list = list.where((f) {
          final name = f.path.split('/').last.toLowerCase();
          return words.any((w) => name.contains(w.toLowerCase()));
        }).toList();
      }
    }

    if (_type != 'الكل') {
      list = list.where((f) {
        if (f is Directory) return false;
        if (_type == 'صور') return _isImage(f.path);
        if (_type == 'فيديو') return _isVideo(f.path);
        if (_type == 'صوت') return _isAudio(f.path);
        if (_type == 'مستندات') return _isDoc(f.path);
        if (_type == 'مضغوط') return _isArchive(f.path);
        return true;
      }).toList();
    }

    list.sort((a, b) {
      final aDir = a is Directory, bDir = b is Directory;
      if (aDir && !bDir) return -1;
      if (!aDir && bDir) return 1;
      final aName = a.path.split('/').last.toLowerCase();
      final bName = b.path.split('/').last.toLowerCase();
      if (_sort == 'الاسم') return aName.compareTo(bName);
      if (_sort == 'الحجم') {
        try { return b.statSync().size.compareTo(a.statSync().size); } catch (_) { return 0; }
      }
      if (_sort == 'التاريخ') {
        try { return b.statSync().modified.compareTo(a.statSync().modified); } catch (_) { return 0; }
      }
      return 0;
    });

    setState(() => _visible = list);
  }

  Future<void> _openFile(File f) async {
    try {
      final res = await OpenFilex.open(f.path);
      if (res.type != ResultType.done) {
        _snack('لا يوجد تطبيق لفتح هذا الملف');
      }
    } catch (e) {
      _snack('خطأ: $e');
    }
  }

  Future<void> _delete(FileSystemEntity f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${f.path.split('/').last}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await f.delete(recursive: true);
        _all.remove(f);
        _apply();
        _snack('تم الحذف');
      } catch (e) {
        _snack('فشل الحذف: $e');
      }
    }
  }

  Future<void> _rename(FileSystemEntity f) async {
    final ctrl = TextEditingController(text: f.path.split('/').last);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إعادة تسمية'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        final parent = f.parent.path;
        await f.rename('$parent/$name');
        _snack('تمت إعادة التسمية');
        await _refresh();
      } catch (e) {
        _snack('فشل: $e');
      }
    }
  }

  Future<void> _share(FileSystemEntity f) async {
    try {
      await Share.shareXFiles([XFile(f.path)]);
    } catch (e) {
      _snack('فشل المشاركة: $e');
    }
  }

  void _copyPath(FileSystemEntity f) {
    Clipboard.setData(ClipboardData(text: f.path));
    _snack('تم نسخ المسار');
  }

  void _info(FileSystemEntity f) async {
    String size = '—';
    String modified = '—';
    try {
      final s = await f.stat();
      size = f is Directory ? 'مجلد' : _fmtSize(s.size);
      modified =
          '${s.modified.day}/${s.modified.month}/${s.modified.year} '
          '${s.modified.hour.toString().padLeft(2, '0')}:'
          '${s.modified.minute.toString().padLeft(2, '0')}';
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.path.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المسار: ${f.path}'),
            const SizedBox(height: 6),
            Text('الحجم: $size'),
            const SizedBox(height: 6),
            Text('آخر تعديل: $modified'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _refresh() async {
    if (_current == null) return;
    await _openNoHistory(_current!);
  }

  void _sortMenu() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['الاسم', 'الحجم', 'التاريخ'].map((s) => ListTile(
            leading: Icon(_sort == s ? Icons.check_circle : Icons.sort),
            title: Text(s),
            onTap: () {
              Navigator.pop(c);
              setState(() => _sort = s);
              _apply();
            },
          )).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _current == null ? 'مدير الملفات الذكي' : _current!.path.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? 'الجذر' : title, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _history.isEmpty ? null : _back,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.sort), onPressed: _sortMenu),
        ],
      ),
      body: Column(
        children: [
          if (!_hasPerm)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_off_outlined, size: 72),
                      const SizedBox(height: 16),
                      const Text('نحتاج صلاحية الوصول للملفات',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                          'سيُطلب منك السماح بإدارة جميع الملفات من إعدادات النظام',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (await Permission.manageExternalStorage.isPermanentlyDenied) {
                            await openAppSettings();
                          } else {
                            await _requestPerms();
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('منح الصلاحية'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) { _query = v; _apply(); },
                decoration: InputDecoration(
                  hintText: 'ابحث: صور هذا الشهر، فيديوهات، pdf...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _query = '';
                            _apply();
                          },
                        )
                      : null,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: ['الكل', 'صور', 'مستندات', 'فيديو', 'صوت', 'مضغوط']
                    .map((label) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _type == label,
                            onSelected: (_) {
                              setState(() => _type = label);
                              _apply();
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
            Expanded(
              child: _visible.isEmpty
                  ? Center(child: Text(_all.isEmpty ? 'المجلد فارغ' : 'لا توجد نتائج'))
                  : ListView.builder(
                      itemCount: _visible.length,
                      itemBuilder: (_, i) {
                        final f = _visible[i];
                        final name = f.path.split('/').last;
                        String sub = '';
                        try {
                          final s = f.statSync();
                          if (f is Directory) {
                            sub = 'مجلد';
                          } else {
                            sub =
                                '${_fmtSize(s.size)} • ${s.modified.day}/${s.modified.month}/${s.modified.year}';
                          }
                        } catch (_) {}
                        return ListTile(
                          leading: CircleAvatar(child: Icon(_iconFor(f))),
                          title: Text(name.isEmpty ? f.path : name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: sub.isEmpty
                              ? null
                              : Text(sub, style: const TextStyle(fontSize: 11)),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'open') {
                                if (f is Directory) _open(f); else _openFile(f as File);
                              }
                              if (v == 'rename') _rename(f);
                              if (v == 'delete') _delete(f);
                              if (v == 'share') _share(f);
                              if (v == 'copy') _copyPath(f);
                              if (v == 'info') _info(f);
                            },
                            itemBuilder: (c) => [
                              const PopupMenuItem(value: 'open', child: Text('فتح')),
                              if (f is File)
                                const PopupMenuItem(value: 'share', child: Text('مشاركة')),
                              const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                              const PopupMenuItem(value: 'copy', child: Text('نسخ المسار')),
                              const PopupMenuItem(value: 'info', child: Text('معلومات')),
                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                          onTap: () {
                            if (f is Directory) _open(f); else _openFile(f as File);
                          },
                        );
                      },
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              color: Colors.grey.withOpacity(0.15),
              child: Text(_status,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}
