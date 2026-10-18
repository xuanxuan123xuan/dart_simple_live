import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';

/// Lets a TV user open a room by pasting a supported link or entering its ID.
class TvOpenLiveLinkDialog extends StatefulWidget {
  const TvOpenLiveLinkDialog({super.key, this.initialSiteId = Constant.kDouyu});

  final String initialSiteId;

  @override
  State<TvOpenLiveLinkDialog> createState() => _TvOpenLiveLinkDialogState();
}

class _TvOpenLiveLinkDialogState extends State<TvOpenLiveLinkDialog> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _parser = LiveRoomLinkParser();
  late String _roomSiteId;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _roomSiteId = Sites.allSites.containsKey(widget.initialSiteId)
        ? widget.initialSiteId
        : Constant.kDouyu;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    setState(() {
      _inputController.text = data!.text!.trim();
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      _error = null;
    });
  }

  Future<void> _open() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final target = await _parser.parse(
        _inputController.text,
        roomSiteId: _roomSiteId,
      );
      if (!mounted) return;
      if (target == null) {
        setState(() {
          _error = '无法识别该直播间。请检查链接或房间号。';
          _resolving = false;
        });
        return;
      }
      Get.back(result: target);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '解析链接失败，请检查网络后重试。';
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = Sites.supportSites;
    return Dialog(
      child: SizedBox(
        width: 760,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: FocusTraversalGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('打开直播间', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _roomSiteId,
                        decoration: const InputDecoration(labelText: '房间号所属平台'),
                        items: [
                          for (final site in sites)
                            DropdownMenuItem(
                              value: site.id,
                              child: Text(site.name),
                            ),
                        ],
                        onChanged: _resolving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _roomSiteId = value);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.tonal(
                      onPressed: _resolving ? null : _paste,
                      child: const Text('粘贴剪贴板'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _open(),
                  decoration: const InputDecoration(
                    labelText: '直播链接或房间号',
                    hintText: '粘贴直播分享链接，或输入上方平台的房间号',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '小红书仅支持直播链接直达；Windows 可播放页面公开的直播流，网页签名功能仅在 Android TV 提供。',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _resolving ? null : Get.back,
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _resolving ? null : _open,
                      child: Text(_resolving ? '正在解析…' : '打开直播'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
