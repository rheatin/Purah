#!/bin/bash
set -e

REAL_INPUT="/tmp/real_desktop5_full_take.mp4"
FINAL_VIDEO="assets/purah-showcase-30s.mp4"
FINAL_GIF="assets/purah-showcase-30s.gif"
BGM="/Users/char/.pi/agent/skills/video-shotcraft/assets/audio/bgm/bgm-tech-house.mp3"

echo "🎬 [video-shotcraft] Editing 30s cinematic product showcase from real Desktop 5 capture..."

# 1. Opener: 3.0s stroke-segment-build title hook
/opt/homebrew/bin/ffmpeg -y -framerate 30 -i "/tmp/master_cuts/cut1/frame_%04d.png" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -t 3.0 \
    /tmp/edit_c1_opener.mp4

# 2. Real Right Rail Close-up: Calendar (5.0s, zoomed-in, menu bar 100% out of frame)
/opt/homebrew/bin/ffmpeg -y -ss 00:00:03.5 -i "$REAL_INPUT" -t 5.0 \
    -vf "crop=1656:1100:1800:100,scale=1920:1080:flags=lanczos,fps=30" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/edit_c2_calendar.mp4

# 3. Real Right Rail Close-up: Music VU Meter (5.0s, zoomed-in, menu bar 100% out of frame)
/opt/homebrew/bin/ffmpeg -y -ss 00:00:08.5 -i "$REAL_INPUT" -t 5.0 \
    -vf "crop=1656:1100:1800:1100,scale=1920:1080:flags=lanczos,fps=30" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/edit_c3_music.mp4

# 4. Real Left Rail Close-up: Network I/O & Vitals (5.0s, zoomed-in, menu bar 100% out of frame)
/opt/homebrew/bin/ffmpeg -y -ss 00:00:16.5 -i "$REAL_INPUT" -t 5.0 \
    -vf "crop=1656:1100:0:100,scale=1920:1080:flags=lanczos,fps=30" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/edit_c4_vitals.mp4

# 5. Real Left Rail Close-up: Script Runway & Empty Trash (5.0s, zoomed-in, menu bar 100% out of frame)
/opt/homebrew/bin/ffmpeg -y -ss 00:00:21.5 -i "$REAL_INPUT" -t 5.0 \
    -vf "crop=1656:1100:0:1100,scale=1920:1080:flags=lanczos,fps=30" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/edit_c5_scripts.mp4

# 6. Real Zero-Block Pullback: Clean Desktop 5 (4.0s, full-screen, menu bar y<88 cropped out 100%)
/opt/homebrew/bin/ffmpeg -y -ss 00:00:25.0 -i "$REAL_INPUT" -t 4.0 \
    -vf "crop=3456:2146:0:88,scale=1920:1080:flags=lanczos,fps=30" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/edit_c6_pullback.mp4

# 7. Brand Outro: 3.0s icon-flip-bloom morph to official Purah icon + GitHub
/opt/homebrew/bin/ffmpeg -y -framerate 30 -i "/tmp/master_cuts/cut9/frame_%04d.png" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -t 3.0 \
    /tmp/edit_c7_outro.mp4

echo "🔗 Concatenating 7 video-shotcraft cuts into master cut..."
cat << 'EOF' > /tmp/vs_concat.txt
file '/tmp/edit_c1_opener.mp4'
file '/tmp/edit_c2_calendar.mp4'
file '/tmp/edit_c3_music.mp4'
file '/tmp/edit_c4_vitals.mp4'
file '/tmp/edit_c5_scripts.mp4'
file '/tmp/edit_c6_pullback.mp4'
file '/tmp/edit_c7_outro.mp4'
EOF

/opt/homebrew/bin/ffmpeg -y -f concat -safe 0 -i /tmp/vs_concat.txt \
    -c copy /tmp/vs_raw_concatenated.mp4

echo "🎵 Mixing Video-Shotcraft BGM (Tech House 120BPM) with audio fades..."
/opt/homebrew/bin/ffmpeg -y -i /tmp/vs_raw_concatenated.mp4 \
    -stream_loop -1 -i "$BGM" \
    -filter_complex "\
      [1:a]volume=0.36,afade=t=in:ss=0:d=1.0,afade=t=out:st=28.0:d=2.0[bgm]; \
      [0:v]fade=t=in:st=0:d=0.5,fade=t=out:st=28.5:d=1.5[vout]" \
    -map "[vout]" -map "[bgm]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -t 30.0 \
    "$FINAL_VIDEO"

echo "🖼️ Rendering optimized high-definition showcase GIF (960x540, 16fps)..."
/opt/homebrew/bin/ffmpeg -y -i "$FINAL_VIDEO" \
    -filter_complex "[0:v]fps=16,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
    "$FINAL_GIF"

echo "✨ Production Complete! 30-Second Video-Shotcraft Master Edited!"
ls -lh "$FINAL_VIDEO" "$FINAL_GIF"
