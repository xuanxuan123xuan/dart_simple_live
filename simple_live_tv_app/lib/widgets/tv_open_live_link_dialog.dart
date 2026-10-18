import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/tv_playback_dialog_theme.dart';

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

    return TvPlaybackDialogSurface(
      key: const Key('tv-open-live-link-dialog'),
      maxWidth: 780,
      maxHeight: 420,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TvPlaybackDialogHeader(
                icon: Icons.link_rounded,
                title: '打开直播间',
                subtitle: '粘贴直播分享链接，或选择平台后输入房间号',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _roomSiteId,
                              decoration:
                                  const InputDecoration(labelText: '房间号所属平台'),
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
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: _resolving ? null : _paste,
                            icon: const Icon(Icons.content_paste_rounded),
                            label: const Text('粘贴剪贴板'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('tv-open-live-link-input'),
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
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x12ffffff),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: TvPlaybackDialogTheme.outlineColor,
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.tips_and_updates_outlined, size: 19),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '输入链接时会尝试识别直播间；如果填写的是房间号，请先选择对应平台。',
                                style: TextStyle(
                                  color: Color(0xbfffffff),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0x2fffffff)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _resolving ? null : Get.back,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _resolving ? null : _open,
                    icon: _resolving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new_rounded),
                    label: Text(_resolving ? '正在解析…' : '打开直播'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
