# РМ-1 (RPi 4) як відеовузол для заміру «від скла до скла»: V399 MJPG -> v4l2jpegdec -> v4l2h264enc (параметри KSIM-017)
# -> RTSP :8554/video0. python3 camserve.py [пристрій=/dev/video0] [WxH@fps=640x480@30] [бітрейт_кбіт=2000] [gop=75]
import sys
import gi
gi.require_version("Gst", "1.0"); gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtspServer, GLib
dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/video0"
size, fps = (sys.argv[2] if len(sys.argv) > 2 else "640x480@30").split("@"); w, h = size.split("x")
kbps = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
gop = int(sys.argv[4]) if len(sys.argv) > 4 else 75
dec = sys.argv[5] if len(sys.argv) > 5 else "v4l2jpegdec"
ctrls = f"controls,video_bitrate={kbps * 1000},h264_i_frame_period={gop},h264_profile=0,repeat_sequence_header=1"
ctrls += sys.argv[7] if len(sys.argv) > 7 else ""   # напр. ",video_bitrate_mode=1" (CBR)
enc = sys.argv[6] if len(sys.argv) > 6 else "v4l2"
encpart = (f"v4l2h264enc extra-controls=\"{ctrls}\" ! video/x-h264,profile=baseline,level=(string)4" if enc == "v4l2" else
           f"x264enc tune=zerolatency speed-preset=ultrafast bitrate={kbps} key-int-max={gop} ! video/x-h264,profile=baseline")
launch = (f"( v4l2src device={dev} ! image/jpeg,width={w},height={h},framerate={fps}/1 ! "
          f"queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream ! {dec} ! videoconvert ! video/x-raw,format=I420 ! "
          f"{encpart} ! "
          f"h264parse ! rtph264pay name=pay0 pt=96 config-interval=1 )")
Gst.init(None)
srv = GstRtspServer.RTSPServer(); srv.set_service("8554")
f = GstRtspServer.RTSPMediaFactory(); f.set_launch(launch); f.set_shared(True)
srv.get_mount_points().add_factory("/video0", f); srv.attach(None)
print("camserve: rtsp://0.0.0.0:8554/video0", launch, flush=True)
GLib.MainLoop().run()
