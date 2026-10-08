# Yerel video örneği

`video-sample.mp4`: 12 saniye, 160×90, 10 fps, sessiz yeşil görüntü;
H.264 Constrained Baseline / avc1. İlk kare testleri ağ kullanmaz.
Bu örnek UHD/HEVC uyumluluğunu doğrulamaz.

FFmpeg ile sentetik olarak üretildi:

```sh
ffmpeg -f lavfi -i "color=c=green:s=160x90:r=10:d=12" -an \
  -c:v libx264 -profile:v baseline -level:v 3.0 -pix_fmt yuv420p \
  -g 10 -movflags +faststart video-sample.mp4
```
