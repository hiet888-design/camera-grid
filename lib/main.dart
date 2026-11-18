import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CameraApp());
}

enum Brand { hikvision, dahua }

String brandName(Brand b) => b == Brand.hikvision ? 'Hikvision' : 'Dahua';

String rtspUrl(Brand b, String user, String pass, String ip,
    {required bool mainStream}) {
  final u = Uri.encodeComponent(user);
  final p = Uri.encodeComponent(pass);
  if (b == Brand.hikvision) {
    final ch = mainStream ? 101 : 102;
    return 'rtsp://$u:$p@$ip:554/Streaming/Channels/$ch';
  }
  final sub = mainStream ? 0 : 1;
  return 'rtsp://$u:$p@$ip:554/cam/realmonitor?channel=1&subtype=$sub';
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xem Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const SetupPage(),
    );
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Brand brand = Brand.hikvision;
  final userCtl = TextEditingController(text: 'admin');
  final passCtl = TextEditingController();
  final subnetCtl = TextEditingController();
  final manualCtl = TextEditingController();

  bool scanning = false;
  double progress = 0;
  List<String> found = [];
  String status = '';

  @override
  void initState() {
    super.initState();
    _autoSubnet();
  }

  Future<void> _autoSubnet() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          final parts = a.address.split('.');
          if (parts.length == 4) {
            if (mounted) setState(() => subnetCtl.text = parts.sublist(0, 3).join('.'));
            return;
          }
        }
      }
    } catch (_) {}
  }

  String? _base() {
    var t = subnetCtl.text.trim();
    if (t.contains('/')) t = t.split('/').first;
    final parts = t.split('.');
    if (parts.length < 3) return null;
    return parts.sublist(0, 3).join('.');
  }

  Future<void> _scan() async {
    final base = _base();
    if (base == null) {
      setState(() => status = 'Lớp mạng không đúng, ví dụ: 192.168.1');
      return;
    }
    setState(() {
      scanning = true;
      progress = 0;
      found = [];
      status = 'Đang quét $base.1 - $base.254 ...';
    });

    final result = <String>[];
    const batch = 32;
    for (int start = 1; start <= 254; start += batch) {
      final futures = <Future<void>>[];
      for (int i = start; i < start + batch && i <= 254; i++) {
        final ip = '$base.$i';
        futures.add(
          Socket.connect(ip, 554, timeout: const Duration(milliseconds: 600))
              .then((s) {
            s.destroy();
            result.add(ip);
          }).catchError((_) {}),
        );
      }
      await Future.wait(futures);
      if (!mounted) return;
      setState(() => progress = (start + batch - 1).clamp(0, 254) / 254);
    }
    result.sort((a, b) =>
        int.parse(a.split('.').last).compareTo(int.parse(b.split('.').last)));
    if (!mounted) return;
    setState(() {
      scanning = false;
      found = result;
      status = 'Tìm thấy ${result.length} thiết bị mở cổng 554';
    });
  }

  void _addManual() {
    final ip = manualCtl.text.trim();
    if (ip.isEmpty || found.contains(ip)) return;
    setState(() {
      found = [...found, ip];
      manualCtl.clear();
      status = 'Có ${found.length} camera';
    });
  }

  void _openGrid() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GridPage(
          brand: brand,
          user: userCtl.text.trim(),
          pass: passCtl.text,
          ips: found,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xem Camera RTSP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Brand>(
            value: brand,
            decoration: const InputDecoration(
                labelText: 'Hãng camera', border: OutlineInputBorder()),
            items: Brand.values
                .map((b) => DropdownMenuItem(value: b, child: Text(brandName(b))))
                .toList(),
            onChanged: (b) => setState(() => brand = b ?? brand),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: userCtl,
            decoration: const InputDecoration(
                labelText: 'User', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passCtl,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subnetCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Lớp mạng cần quét (ví dụ 192.168.1)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: scanning ? null : _scan,
            icon: const Icon(Icons.search),
            label: const Text('Quét camera'),
          ),
          if (scanning) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
          if (status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(status),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: manualCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Thêm IP thủ công',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _addManual, icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 12),
          if (found.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: found
                  .map((ip) => Chip(
                        label: Text(ip),
                        onDeleted: () => setState(() => found = found.where((x) => x != ip).toList()),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _openGrid,
              icon: const Icon(Icons.grid_view),
              label: Text('Xem ${found.length} camera dạng lưới'),
            ),
          ],
        ],
      ),
    );
  }
}

class GridPage extends StatelessWidget {
  final Brand brand;
  final String user;
  final String pass;
  final List<String> ips;

  const GridPage({
    super.key,
    required this.brand,
    required this.user,
    required this.pass,
    required this.ips,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${ips.length} camera')),
      body: GridView.builder(
        // cacheExtent = 0: ô nào cuộn ra khỏi màn hình sẽ bị hủy, ô cuộn tới mới chạy video
        cacheExtent: 0,
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 16 / 9,
        ),
        itemCount: ips.length,
        itemBuilder: (context, i) {
          final ip = ips[i];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(ip)),
                  body: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CamTile(
                        ip: ip,
                        url: rtspUrl(brand, user, pass, ip, mainStream: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: CamTile(
              key: ValueKey(ip),
              ip: ip,
              url: rtspUrl(brand, user, pass, ip, mainStream: false),
            ),
          );
        },
      ),
    );
  }
}

class CamTile extends StatefulWidget {
  final String ip;
  final String url;

  const CamTile({super.key, required this.ip, required this.url});

  @override
  State<CamTile> createState() => _CamTileState();
}

class _CamTileState extends State<CamTile> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  final List<StreamSubscription> subs = [];
  bool hasVideo = false;
  String message = 'Đang kết nối...';

  String get safeUrl => widget.url.replaceFirst(RegExp(r':[^:@/]*@'), ':****@');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await (player.platform as dynamic).setProperty('rtsp-transport', 'tcp');
    } catch (_) {}

    subs.add(player.stream.width.listen((w) {
      if (!mounted) return;
      setState(() {
        hasVideo = (w ?? 0) > 0;
        if (hasVideo) message = '';
      });
    }));
    subs.add(player.stream.error.listen((e) {
      if (mounted) setState(() => message = 'Lỗi: $e');
    }));
    subs.add(player.stream.log.listen((l) {
      if (!mounted || hasVideo) return;
      if (l.level == 'error' || l.level == 'fatal' || l.level == 'warn') {
        setState(() => message = l.text.trim());
      }
    }));
    subs.add(player.stream.buffering.listen((b) {
      if (mounted && b && !hasVideo) setState(() => message = 'Đang tải hình...');
    }));

    await player.setVolume(0);
    await player.open(Media(widget.url));
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.cover,
          ),
          if (!hasVideo)
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam, size: 36, color: Colors.white24),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        safeUrl,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.ip,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
