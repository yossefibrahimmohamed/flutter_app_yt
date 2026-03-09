import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Downloader By Youssef Ibrahim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        primarySwatch: Colors.red,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        primarySwatch: Colors.red,
      ),
      themeMode: _themeMode,
      home: YTDownloaderPage(toggleTheme: _toggleTheme),
    );
  }
}

class YTDownloaderPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  const YTDownloaderPage({super.key, required this.toggleTheme});

  @override
  State<YTDownloaderPage> createState() => _YTDownloaderPageState();
}

class _YTDownloaderPageState extends State<YTDownloaderPage> {
  final TextEditingController _urlController = TextEditingController();
  String _selectedResolution = '720p';
  String? _downloadPath;
  double _progress = 0.0;
  String _statusMessage = '';
  bool _isDownloading = false;

  final List<String> _resolutions = ['144p', '240p', '360p', '480p', '720p', '1080p'];

  @override
  void initState() {
    super.initState();
    _initDownloadPath();
  }

  Future<void> _initDownloadPath() async {
    if (Platform.isAndroid) {
      _downloadPath = "/storage/emulated/0/Download";
      if (!Directory(_downloadPath!).existsSync()) {
        final dir = await getExternalStorageDirectory();
        _downloadPath = dir?.path;
      }
    } else {
      final dir = await getDownloadsDirectory();
      _downloadPath = dir?.path;
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectPath() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _downloadPath = result;
        _statusMessage = '✅ Save location selected: $result';
      });
    }
  }

  Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.videos,
      Permission.audio,
    ].request();

    return (statuses[Permission.storage]?.isGranted ?? false) ||
        (statuses[Permission.manageExternalStorage]?.isGranted ?? false) ||
        ((statuses[Permission.videos]?.isGranted ?? false) && (statuses[Permission.audio]?.isGranted ?? false));
  }

  Future<void> _downloadVideo({bool isAudioOnly = false, bool isPlaylist = false, bool isShortest = false}) async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _downloadPath == null) {
      setState(() => _statusMessage = '⚠ Provide URL and select location');
      return;
    }

    if (!await _requestPermission()) {
      setState(() => _statusMessage = '❌ Permission Denied');
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = isPlaylist ? '⏳ Fetching playlist...' : (isAudioOnly ? '⏳ Downloading MP3...' : '⏳ Downloading video...');
    });

    final yt = YoutubeExplode();
    try {
      if (isPlaylist) {
        var playlist = await yt.playlists.get(url);
        var videos = await yt.playlists.getVideos(playlist.id).toList();
        int downloadedCount = 0;

        for (var video in videos) {
          var manifest = await yt.videos.streamsClient.getManifest(video.id);
          var streamInfo = manifest.muxed.reduce((curr, next) => curr.videoQuality.index > next.videoQuality.index ? curr : next);
          var stream = yt.videos.streamsClient.get(streamInfo);
          var fileName = '${downloadedCount + 1} - ${video.title}.${streamInfo.container.name}'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
          var file = File('$_downloadPath/$fileName');
          await stream.pipe(file.openWrite());
          downloadedCount++;
          setState(() {
            _progress = downloadedCount / videos.length;
            _statusMessage = '⏳ Downloaded $downloadedCount/${videos.length} videos';
          });
        }
        _statusMessage = '✅ Playlist downloaded successfully!';
      } else {
        var video = await yt.videos.get(url);
        var manifest = await yt.videos.streamsClient.getManifest(video.id);
        StreamInfo streamInfo;
        
        if (isAudioOnly) {
          streamInfo = manifest.audioOnly.withHighestBitrate();
        } else if (isShortest) {
          // Find shortest/lowest quality
          streamInfo = manifest.muxed.reduce((curr, next) => curr.videoQuality.index < next.videoQuality.index ? curr : next);
        } else {
          var quality = _selectedResolution.replaceAll('p', '');
          var streams = manifest.muxed.where((s) => s.videoQuality.toString().contains(quality)).toList();
          streamInfo = streams.isNotEmpty 
              ? streams.first 
              : manifest.muxed.reduce((curr, next) => curr.videoQuality.index > next.videoQuality.index ? curr : next);
        }

        var stream = yt.videos.streamsClient.get(streamInfo);
        var fileName = '${video.title}.${isAudioOnly ? 'mp3' : streamInfo.container.name}'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
        var file = File('$_downloadPath/$fileName');
        var output = file.openWrite();
        var size = streamInfo.size.totalBytes;
        var count = 0;

        await for (final data in stream) {
          count += data.length;
          if (mounted) setState(() => _progress = count / size);
          output.add(data);
        }
        await output.close();
        _statusMessage = '✅ Success! Saved to: ${file.path}';
      }
      _showSuccessDialog('Download Completed Successfully!');
    } catch (e) {
      setState(() => _statusMessage = '❌ Error: ${e.toString()}');
    } finally {
      yt.close();
      setState(() => _isDownloading = false);
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 30, errorBuilder: (c, e, s) => const Icon(Icons.download)),
            const SizedBox(width: 10),
            const Text('YT Downloader'),
          ],
        ),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.toggleTheme,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Image.asset(
              'logo/YT Downloader By Yossef Ibrahim.png',
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.movie_filter, size: 100, color: Colors.red),
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'YouTube URL',
                hintText: 'Enter Video or Playlist URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 15),

            const Text('Resolution:', style: TextStyle(fontWeight: FontWeight.bold)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: _resolutions.map((r) => ButtonSegment(value: r, label: Text(r))).toList(),
                selected: {_selectedResolution},
                onSelectionChanged: (newSelection) {
                  setState(() => _selectedResolution = newSelection.first);
                },
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : () => _downloadVideo(),
                    icon: const Icon(Icons.video_library),
                    label: const Text('Video'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : () => _downloadVideo(isPlaylist: true),
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Playlist'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : () => _downloadVideo(isAudioOnly: true),
                    icon: const Icon(Icons.audiotrack),
                    label: const Text('MP3'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : () => _downloadVideo(isShortest: true),
                    icon: const Icon(Icons.compress),
                    label: const Text('Shortest'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Center(
              child: ElevatedButton.icon(
                onPressed: _selectPath,
                icon: Image.asset(
                  'logo/folder.png',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder_open),
                ),
                label: const Text('Select Path'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.red, elevation: 0),
              ),
            ),
            const SizedBox(height: 30),

            if (_isDownloading || _progress > 0) ...[
              LinearProgressIndicator(value: _progress, minHeight: 10, borderRadius: BorderRadius.circular(5)),
              const SizedBox(height: 10),
              Text('${(_progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 20),

            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            
            const SizedBox(height: 50),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Version 4.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('By Youssef Ibrahim', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
