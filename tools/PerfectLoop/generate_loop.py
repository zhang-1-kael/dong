from src.findbestframe import LoopFrameFinder
from src.trim_logic import LoopTrimmer
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("video_path", help="Path to input video")
    parser.add_argument("--output_chart", default="similarity_matrix.png")
    parser.add_argument("--trim_output", default="looped_trim.mp4")

    args = parser.parse_args()

    finder = LoopFrameFinder(args.video_path)
    result = finder.run(args.output_chart)

    trimmer = LoopTrimmer(args.video_path)
    trimmer.trim(result["start_frame"], result["end_frame"], result["fps"], args.trim_output)
