import os
import cv2
import argparse
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity
from skimage.metrics import structural_similarity as ssim


def extract_frame(video_path, frame_index, resize_to=(1280, 720)):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError(f"Cannot open video file: {video_path}")

    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
    ret, frame = cap.read()
    cap.release()

    if not ret:
        raise ValueError(f"Could not read frame {frame_index} from {video_path}")

    return cv2.resize(frame, resize_to)


def compute_hist_embedding(frame):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    h_hist = cv2.calcHist([hsv], [0], None, [32], [0, 180])
    s_hist = cv2.calcHist([hsv], [1], None, [32], [0, 256])
    v_hist = cv2.calcHist([hsv], [2], None, [32], [0, 256])

    h_hist = cv2.normalize(h_hist, h_hist).flatten()
    s_hist = cv2.normalize(s_hist, s_hist).flatten()
    v_hist = cv2.normalize(v_hist, v_hist).flatten()

    return np.concatenate([h_hist, s_hist, v_hist])


def compute_similarity(frame1, frame2):
    emb1 = compute_hist_embedding(frame1).reshape(1, -1)
    emb2 = compute_hist_embedding(frame2).reshape(1, -1)
    hist_sim = cosine_similarity(emb1, emb2)[0][0]

    gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
    ssim_score, diff = ssim(gray1, gray2, full=True)

    diff_normalized = (diff * 255).astype(np.uint8)
    diff_color = cv2.applyColorMap(diff_normalized, cv2.COLORMAP_JET)

    return hist_sim, ssim_score, diff_color


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", help="Input video path")
    parser.add_argument("--output", required=True, help="Output directory")
    parser.add_argument("--start", type=int, required=True, help="Start frame index")
    parser.add_argument("--end", type=int, required=True, help="End frame index")
    parser.add_argument("--resize", default="1280x720", help="Resize format (WxH)")
    parser.add_argument("--no-diff-map", action="store_true", help="Do not save SSIM diff map")

    args = parser.parse_args()
    w, h = map(int, args.resize.lower().split("x"))
    resize_to = (w, h)

    os.makedirs(args.output, exist_ok=True)

    print(f"[INFO] Extracting frames {args.start} and {args.end} from {args.video}...")
    frame_start = extract_frame(args.video, args.start, resize_to)
    frame_end = extract_frame(args.video, args.end, resize_to)

    print("[INFO] Computing similarity...")
    hist_score, ssim_score, ssim_diff_map = compute_similarity(frame_start, frame_end)

    cv2.imwrite(os.path.join(args.output, f"frame_{args.start}_start.png"), frame_start)
    cv2.imwrite(os.path.join(args.output, f"frame_{args.end}_end.png"), frame_end)

    if not args.no_diff_map:
        diff_map_path = os.path.join(args.output, "ssim_diff_map.png")
        cv2.imwrite(diff_map_path, ssim_diff_map)
        print(f"[INFO] SSIM difference map saved to: {diff_map_path}")

    print(f"[RESULT] Start frame: {args.start}")
    print(f"[RESULT] End frame: {args.end}")
    print(f"[RESULT] Histogram Similarity: {hist_score:.4f}")
    print(f"[RESULT] SSIM Score: {ssim_score:.4f}")


if __name__ == "__main__":
    main()
