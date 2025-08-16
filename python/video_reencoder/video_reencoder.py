import os
import subprocess
from concurrent.futures import ThreadPoolExecutor

def process_video(input_file, output_dir):
    """处理单个视频文件"""
    try:
        # 获取文件名和扩展名
        base_name = os.path.basename(input_file)
        file_name, ext = os.path.splitext(base_name)

        # 构建输出文件名和路径
        # output_name = f"new-{file_name}.mp4"
        output_name = f"{file_name}.mp4"
        output_path = os.path.join(output_dir, output_name)

        # 构建FFmpeg命令
        cmd = [
            'ffmpeg',
            '-i', input_file,
            '-c:v', 'libx264',
            '-preset', 'slow',
            '-c:a', 'copy',
            output_path
        ]

        # 执行命令
        subprocess.run(cmd, check=True)
        print(f"成功处理: {input_file} -> {output_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"处理失败: {input_file}, 错误: {e}")
        return False
    except Exception as e:
        print(f"发生意外错误: {input_file}, 错误: {e}")
        return False

def batch_process_videos(input_dir, output_dir, max_workers=4):
    """批量处理视频文件"""
    # 确保输出目录存在
    os.makedirs(output_dir, exist_ok=True)

    # 获取所有视频文件
    video_files = []
    for root, _, files in os.walk(input_dir):
        for file in files:
            if file.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.flv')):
                video_files.append(os.path.join(root, file))

    if not video_files:
        print("未找到视频文件")
        return

    print(f"找到 {len(video_files)} 个视频文件待处理")

    # 使用线程池并行处理
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        results = list(executor.map(lambda f: process_video(f, output_dir), video_files))

    success_count = sum(results)
    print(f"处理完成: 成功 {success_count} 个, 失败 {len(results)-success_count} 个")

if __name__ == "__main__":
    # 设置输入和输出目录
    input_directory = "input"  # 替换为你的视频目录
    output_directory = "videos"  # 替换为你的输出目录

    # 开始批量处理
    batch_process_videos(input_directory, output_directory)
