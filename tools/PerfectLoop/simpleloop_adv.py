import cv2
import os
import argparse
import numpy as np
from skimage.metrics import structural_similarity as ssim

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
    new_len = max(1, int(len(frames) / speed_factor))
    indices = np.linspace(0, len(frames) - 1, new_len).astype(int)
    return [frames[i] for i in indices]

def compute_difference_mask(frame1, frame2, threshold=0.25, blur_ksize=15):
    gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
    _, diff = ssim(gray1, gray2, full=True)
    diff = 1 - diff  # SSIM similarity inverted → difference map [0,1]
    mask = (diff > threshold).astype(np.float32)
    mask = cv2.GaussianBlur(mask, (blur_ksize, blur_ksize), 0)
    mask = np.clip(mask, 0, 1)
    return mask[..., None]  # Add channel dim for broadcasting

def hybrid_morph_frames(last_frame, first_frame, steps=15, diff_mask=None):
    blended = []
    if diff_mask is None:
        diff_mask = np.ones_like(first_frame, dtype=np.float32)
    last_f = last_frame.astype(np.float32)
    first_f = first_frame.astype(np.float32)
    diff_mask_f = diff_mask.astype(np.float32)
    inv_mask = 1.0 - diff_mask_f

    for i in range(steps):
        alpha = (i + 1) / steps
        # Morph dissimilar regions with weighted blend
        morph_part = (1 - alpha) * last_f + alpha * first_f
        # Composite: morph dissimilar, fade similar directly to first frame
        blended_frame = morph_part * diff_mask_f + first_f * inv_mask
        blended_frame = np.clip(blended_frame, 0, 255).astype(np.uint8)
        blended.append(blended_frame)
    return blended

def create_loop_video(input_path, output_path, speed_factor=1.0, morph_steps=15):
    frames = read_all_frames(input_path)
    if len(frames) < 2:
        raise ValueError("Video must have at least 2 frames.")

    first_frame = frames[0]
    last_frame = frames[-1]

    print("[INFO] Computing difference mask between first and last frame...")
    diff_mask = compute_difference_mask(last_frame, first_frame, threshold=0.25, blur_ksize=15)

    print("[INFO] Morphing last frame into first frame using difference mask...")
    morph_sequence = hybrid_morph_frames(last_frame, first_frame, steps=morph_steps, diff_mask=diff_mask)

    print(f"[INFO] Adjusting video speed by factor {speed_factor}...")
    base_frames = adjust_speed(frames, speed_factor)

    full_sequence = base_frames + morph_sequence

    height, width = first_frame.shape[:2]
    cap = cv2.VideoCapture(input_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    cap.release()
    adjusted_fps = fps * speed_factor

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, adjusted_fps, (width, height))

    print(f"[INFO] Writing {len(full_sequence)} frames to output video...")
    for f in full_sequence:
        out.write(f)
    out.release()

    print(f"[INFO] Looping video saved to: {output_path}")

def cli():
    parser = argparse.ArgumentParser(description="Create a seamless looping video by morphing dissimilar areas only.")
    parser.add_argument("input", help="Path to input video")
    parser.add_argument("output", help="Path to output looped video")
    parser.add_argument("--speed", type=float, default=1.0, help="Playback speed factor (e.g., 0.5 for slow, 1.5 for fast)")
    parser.add_argument("--morph_steps", type=int, default=15, help="Number of morph frames from last to first")

    args = parser.parse_args()
    create_loop_video(args.input, args.output, speed_factor=args.speed, morph_steps=args.morph_steps)

if __name__ == "__main__":
    cli()

# python simpleloop_adv.py test/hk_greenpath.mkv test/hk_greenpath_looped_adv2.mkv --speed 1.0 --morph_steps 12