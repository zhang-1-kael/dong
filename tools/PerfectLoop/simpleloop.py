import cv2
import os
import argparse
import numpy as np

def read_all_frames(video_path):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError(f"Cannot open video file: {video_path}")
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame)
    cap.release()
    return frames

def adjust_speed(frames, speed_factor):
    if speed_factor == 1.0:
        return frames
    new_len = int(len(frames) / speed_factor)
    indices = np.linspace(0, len(frames) - 1, new_len).astype(int)
    return [frames[i] for i in indices]

def crossfade_to_first(trailing_frames, first_frame, steps):
    """Fade last N frames into the first frame, preserving forward motion."""
    blended_frames = []
    for i in range(steps):
        alpha = 0.9 - (i + 1) / steps  # 1 → 0
        base_frame = trailing_frames[i]
        blended = cv2.addWeighted(base_frame, alpha, first_frame, 1 - alpha, 0)
        blended_frames.append(blended)
    return blended_frames

def create_loop_video(input_path, output_path, speed_factor=1.0, morph_steps=15):
    frames = read_all_frames(input_path)
    if len(frames) < morph_steps + 1:
        raise ValueError(f"Video must have more than {morph_steps} frames.")

    first_frame = frames[0]
    base_frames = adjust_speed(frames, speed_factor)

    print(f"[INFO] Blending last {morph_steps} frames into the first frame...")
    trailing_frames = base_frames[-morph_steps:]
    morph_sequence = crossfade_to_first(trailing_frames, first_frame, morph_steps)

    # Build the final frame sequence
    looped_sequence = base_frames + morph_sequence

    height, width = first_frame.shape[:2]
    fps = cv2.VideoCapture(input_path).get(cv2.CAP_PROP_FPS)
    adjusted_fps = fps * speed_factor

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, adjusted_fps, (width, height))

    for frame in looped_sequence:
        out.write(frame)
    out.release()

    print(f"[INFO] Looped video saved to: {output_path}")

def cli():
    parser = argparse.ArgumentParser(description="Create a seamless loop by fading last frames into the first.")
    parser.add_argument("input", help="Path to input video")
    parser.add_argument("output", help="Path to output looped video")
    parser.add_argument("--speed", type=float, default=1.0,
                        help="Playback speed factor (e.g., 0.5 = slow down, 1.5 = speed up)")
    parser.add_argument("--morph_steps", type=int, default=15,
                        help="Number of trailing frames to crossfade into first frame")

    args = parser.parse_args()
    create_loop_video(args.input, args.output, speed_factor=args.speed, morph_steps=args.morph_steps)

if __name__ == "__main__":
    cli()

# python simpleloop.py test/hk_greenpath.mkv test/hk_greenpath_looped_adv.mkv --speed 1.0 --morph_steps 25