from src.findbestframe import LoopFrameFinder
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("video_path", help="Path to input video")
    parser.add_argument("--output", default="similarity_matrix.png", help="Output chart path")
    args = parser.parse_args()

    finder = LoopFrameFinder(args.video_path)
    result = finder.run(
        output_chart=f"{args.output}/full_similarity.png",
        focused_chart=f"{args.output}/focused_similarity.png"
        )
    print(f"[RESULT] Best match: frame {result['start_frame']} → {result['end_frame']} "
      f"(hist_score: {result['hist_similarity']:.4f}, ssim_score: {result['ssim_similarity']:.4f})")

