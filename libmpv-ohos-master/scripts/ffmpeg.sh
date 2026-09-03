#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/ffmpeg

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding FFmpeg..."
elif [ "${1:-}" == "clean" ]; then
	rm -rf .build
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

mkdir -p .build
cd .build

# 白名单取舍见 BUILD-NOTES §2。以下几项是第二轮收窄时移除的，均有据可查，勿盲目加回：
#   rtsp/rtp/sdp demuxer  已确认消费方 LiVify 全仓无 RTSP 引用；rtpdec_*.c 文件数最多。
#   原生 av1 decoder      与 libdav1d 功能重复；FFmpeg 的 av1 解码器主要服务 hwaccel，
#                         而 OHOS 侧没有 av1_oh，软解走 libdav1d 即可。
#   wmav2                 直播场景不存在 WMA 音轨。
#   png/mjpeg encoder     仅 mpv 截图会用到，已确认消费方不通过 mpv 截图。
#                         注意 png/mjpeg decoder 仍保留（封面图等附加图片可能用到）。
#   async/cache/concat/subfile protocol
#                         直播不用。注意 mpv 的缓存是内部 demuxer cache，
#                         与 FFmpeg 的 cache: 协议无关，勿混淆。
# 仍可评估的候选：aac_fixed（定点 AAC，aarch64 有 FPU，FFmpeg 不会自动选它）、
#                mp3on4 / mp3on4float（MP4 封装里的 MP3，罕见）。
#
# 注意：configure 的参数是反斜杠续行，中间不能插 # 注释——注释会吃掉后续所有参数。
../configure \
  --prefix=$DEST \
  --arch=aarch64 \
  --cpu=armv8-a \
  --target-os=linux \
  --enable-static \
  --disable-shared \
  --enable-version3 \
  --enable-pic \
  --disable-doc \
  --disable-programs \
  \
  --enable-cross-compile \
  --cc="$CC" \
  --extra-cflags="-I$DEST/include" \
  --extra-ldflags="-L$DEST/lib" \
  --enable-libdav1d \
  --enable-mbedtls \
  --disable-vulkan \
  \
  --disable-everything \
  --enable-avfilter \
  --enable-network \
  --enable-swscale \
  --enable-swresample \
  \
  --disable-devices \
  --disable-avdevice \
  \
  --enable-ohcodec \
  \
  --enable-decoder=h264,hevc,h264_oh,hevc_oh \
  --enable-decoder=libdav1d,vp9,vp8,mjpeg,png \
  --enable-decoder=aac,aac_fixed,aac_latm \
  --enable-decoder=mp3,mp3float,mp3on4,mp3on4float \
  --enable-decoder=opus,flac,vorbis,ac3,eac3 \
  --enable-decoder=pcm_s16le,pcm_s16be,pcm_s32le,pcm_f32le,pcm_u8,pcm_mulaw,pcm_alaw \
  \
  --enable-demuxer=flv,live_flv,hls,mpegts,mov,matroska \
  --enable-demuxer=ogg,aac,mp3,flac,wav \
  \
  --enable-protocol=file,http,https,tcp,tls,udp \
  --enable-protocol=rtmp,rtmps,rtmpt,rtmpts,rtmpe \
  --enable-protocol=hls,crypto,data,pipe,fd \
  \
  --enable-parser=h264,hevc,av1,vp8,vp9,aac,aac_latm,mpegaudio,opus,flac,png \
  \
  --enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb \
  --enable-bsf=extract_extradata,vp9_superframe,av1_frame_split \
  --enable-bsf=h264_redundant_pps,dump_extradata \
  \
  --enable-filter=scale,format,aformat,aresample,null,anull \
  --enable-filter=setpts,asetpts,volume,atempo,pan,fps
make -j$CORES
make install

popd