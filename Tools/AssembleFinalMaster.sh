#!/bin/bash
set -e

CUTS_DIR="/tmp/master_cuts"
OUTPUT_VIDEO="assets/purah-showcase-30s.mp4"
OUTPUT_GIF="assets/purah-showcase-30s.gif"
BGM="/Users/char/.pi/agent/skills/video-shotcraft/assets/audio/bgm/bgm-tech-house.mp3"

echo "🎬 Encoding individual cuts..."
for i in {1..9}; do
    /opt/homebrew/bin/ffmpeg -y -framerate 30 -i "$CUTS_DIR/cut$i/frame_%04d.png" \
        -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
        "/tmp/master_cut_$i.mp4"
done

echo "🔗 Concatenating all 9 cuts..."
cat << 'EOF' > /tmp/concat_master.txt
file '/tmp/master_cut_1.mp4'
file '/tmp/master_cut_2.mp4'
file '/tmp/master_cut_3.mp4'
file '/tmp/master_cut_4.mp4'
file '/tmp/master_cut_5.mp4'
file '/tmp/master_cut_6.mp4'
file '/tmp/master_cut_7.mp4'
file '/tmp/master_cut_8.mp4'
file '/tmp/master_cut_9.mp4'
EOF

/opt/homebrew/bin/ffmpeg -y -f concat -safe 0 -i /tmp/concat_master.txt \
    -c copy /tmp/master_video_raw.mp4

echo "🎵 Mixing Video-Shotcraft BGM (Modern Elevation 120BPM) & audio fades..."
/opt/homebrew/bin/ffmpeg -y -i /tmp/master_video_raw.mp4 \
    -stream_loop -1 -i "$BGM" \
    -filter_complex "\
      [1:a]volume=0.36,afade=t=in:ss=0:d=1.2,afade=t=out:st=31.5:d=2.0[bgm]; \
      [0:v]fade=t=in:st=0:d=0.5,fade=t=out:st=32.0:d=1.5[vout]" \
    -map "[vout]" -map "[bgm]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -t 33.5 \
    "$OUTPUT_VIDEO"

echo "🖼️ Rendering ultra-smooth high-definition GIF (960px, 16fps)..."
/opt/homebrew/bin/ffmpeg -y -i "$OUTPUT_VIDEO" \
    -filter_complex "[0:v]fps=16,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUTPUT_GIF"

echo "✨ Production Complete!"
ls -lh "$OUTPUT_VIDEO" "$OUTPUT_GIF"
