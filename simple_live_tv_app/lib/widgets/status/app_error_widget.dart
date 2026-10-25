import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:lottie/lottie.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class AppErrorWidget extends StatefulWidget {
  final Function()? onRefresh;
  final String errorMsg;
  const AppErrorWidget({this.errorMsg = "", this.onRefresh, Key? key})
      : super(key: key);

  @override
  State<AppErrorWidget> createState() => _AppErrorWidgetState();
}

class _AppErrorWidgetState extends State<AppErrorWidget> {
  final _retryFocus = AppFocusNode();

  @override
  void dispose() {
    _retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LottieBuilder.asset(
              'assets/lotties/error.json',
              width: 200.w,
              repeat: false,
            ),
            AppStyle.vGap24,
            Text(
              widget.errorMsg.isEmpty ? "出错了，请稍后重试" : widget.errorMsg,
              textAlign: TextAlign.center,
              style: AppStyle.textStyleWhite,
            ),
            if (widget.onRefresh != null) ...[
              AppStyle.vGap24,
              HighlightButton(
                focusNode: _retryFocus,
                text: "重试",
                iconData: Icons.refresh,
                autofocus: true,
                onTap: widget.onRefresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
