import 'package:flutter/material.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/widgets/cover.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';

class GridItemTile extends StatefulWidget {
  const GridItemTile({
    super.key,
    required this.title,
    this.cover,
    this.subtitle,
    this.onTap,
    this.headers,
  });
  final String title;
  final String? cover;
  final String? subtitle;
  final Function()? onTap;
  final Map<String, String>? headers;

  @override
  State<GridItemTile> createState() => _GridItemTileState();
}

class _GridItemTileState extends State<GridItemTile> {
  bool _isHover = false;

  Widget _buildAndroid(BuildContext context) {
    const radius = Radius.circular(YeflixStyle.radiusSm);
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(radius),
            color: YeflixStyle.surfaceAlt,
          ),
          clipBehavior: Clip.antiAlias,
          child: Cover(
            alt: widget.title,
            url: widget.cover,
            headers: widget.headers,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: radius,
                bottomRight: radius,
              ),
              gradient: YeflixStyle.cardScrim,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.all(radius),
              onTap: () {
                widget.onTap?.call();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (event) {
        setState(() {
          _isHover = true;
        });
      },
      onExit: (event) {
        setState(() {
          _isHover = false;
        });
      },
      child: Column(
        // 居左
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                widget.onTap?.call();
              },
              child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedScale(
                    scale: _isHover ? 1.05 : 1,
                    duration: const Duration(milliseconds: 80),
                    child: Cover(
                      alt: widget.title,
                      url: widget.cover,
                      headers: widget.headers,
                    ),
                  )),
            ),
          ),
          const SizedBox(height: 8),
          // 文字只显示一行
          SizedBox(
            height: 20,
            child: Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.subtitle != null)
            Text(
              widget.subtitle.toString(),
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
