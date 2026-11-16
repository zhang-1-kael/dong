import cv2
import os
import argparse

class VideoTrimmer:
    def __init__(self, video_path):
        self.video_path = video_path
        self.cap = cv2.VideoCapture(video_path)
        if not self.cap.isOpened():
            raise IOError(f"Cannot open video file: {video_path}")
        self.fps = self.cap.get(cv2.CAP_PROP_FPS)
        self.width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.frame_count = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))

    def trim_and_save(self, start_frame, end_frame, output_path):
        if start_frame < 0 or end_frame >= self.frame_count or start_frame > end_frame:
            raise ValueError(f"Invalid frame range: start={start_frame}, end={end_frame}, total_frames={self.frame_count}")

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

        fourcc = cv2.VideoWriter_fourcc(*'mp4v')  # Use mp4v for .mp4 output
        out = cv2.VideoWriter(output_path, fourcc, self.fps, (self.width, self.height))

        # Set video position to start_frame
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

        print(f"[INFO] Trimming video from frame {start_frame} to {end_frame}...")
        for frame_num in range(start_frame, end_frame + 1):
            ret, frame = self.cap.read()
            if not ret:
                print(f"[WARN] Frame read failed at frame {frame_num}, stopping early.")
                break
            out.write(frame)

        out.release()
        print(f"[INFO] Trimmed video saved to: {output_path}")

def cli():
    parser = argparse.ArgumentParser(description="Trim a video by specifying start and end frames.")
    parser.add_argument("video_path", help="Path to the input video file")
    parser.add_argument("start_frame", type=int, help="Start frame index (0-based)")
    parser.add_argument("end_frame", type=int, help="End frame index (inclusive)")
    parser.add_argument("-o", "--output", default=None, help="Output trimmed video path (optional)")
    args = parser.parse_args()

    # Determine output path if not provided
    if args.output is None:
        base, ext = os.path.splitext(args.video_path)
        args.output = f"{base}_trimmed_{args.start_frame}_{args.end_frame}{ext}"

    trimmer = VideoTrimmer(args.video_path)
    trimmer.trim_and_save(args.start_frame, args.end_frame, args.output)

if __name__ == "__main__":
    cli()
