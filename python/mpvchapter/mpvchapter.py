#!/usr/bin/env python3
"""
MPVChapter - Automatic Video Chapter Extraction
Extracts chapters from video files by detecting silence segments.

Usage:
    python mpvchapter.py
    (Configure settings in config.json)
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Dict, Any
from dataclasses import dataclass
import logging

@dataclass
class SilenceSegment:
    """Represents a silence segment in the audio."""
    start: float
    end: float
    duration: float

@dataclass
class ChapterMark:
    """Represents a chapter mark."""
    time: float
    title: str
    index: int

class VideoChapterExtractor:
    """Main class for extracting chapters from video files."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self._setup_logging()
        self.ffmpeg_path = self._find_ffmpeg()
        
    def _setup_logging(self):
        """Setup logging based on configuration."""
        log_config = self.config.get('logging', {})
        level = getattr(logging, log_config.get('level', 'INFO'))
        format_str = log_config.get('format', '%(asctime)s - %(levelname)s - %(message)s')
        
        logging.basicConfig(level=level, format=format_str)
        self.logger = logging.getLogger(__name__)
        
    def _find_ffmpeg(self) -> str:
        """Find FFmpeg executable."""
        # Try common FFmpeg paths
        ffmpeg_paths = ['ffmpeg', 'ffmpeg.exe']
        
        # Add common installation paths on Windows
        if os.name == 'nt':
            program_files = os.environ.get('PROGRAMFILES', 'C:\\Program Files')
            ffmpeg_paths.extend([
                os.path.join(program_files, 'ffmpeg', 'bin', 'ffmpeg.exe'),
                os.path.join(program_files, 'ffmpeg', 'bin', 'ffmpeg'),
            ])
        
        for path in ffmpeg_paths:
            try:
                result = subprocess.run([path, '-version'], 
                                     capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    self.logger.info(f"Found FFmpeg at: {path}")
                    return path
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                continue
        
        raise RuntimeError("FFmpeg not found. Please install FFmpeg and ensure it's in PATH.")
    
    def get_video_duration(self, video_path: str) -> Optional[float]:
        """Get video duration using FFprobe."""
        try:
            cmd = [
                self.ffmpeg_path.replace('ffmpeg', 'ffprobe'),
                '-v', 'quiet',
                '-show_entries', 'format=duration',
                '-of', 'json',
                video_path
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                duration = float(data['format']['duration'])
                self.logger.info(f"Video duration: {duration:.2f} seconds")
                return duration
            else:
                self.logger.error(f"Failed to get duration: {result.stderr}")
                return None
        except Exception as e:
            self.logger.error(f"Error getting video duration: {e}")
            return None
    
    def detect_silences(self, video_path: str) -> List[SilenceSegment]:
        """Detect silence segments using FFmpeg's silencedetect filter."""
        silences = []
        
        # Get detection parameters from config
        detection_config = self.config.get('detection', {})
        noise_threshold = detection_config.get('noise_threshold_db', -30)
        min_silence = detection_config.get('min_silence', 1.0)
        
        cmd = [
            self.ffmpeg_path,
            '-i', video_path,
            '-af', f'silencedetect=noise={noise_threshold}dB:d={min_silence}',
            '-f', 'null',
            '-'
        ]
        
        self.logger.info(f"Detecting silences with threshold: {noise_threshold}dB, min duration: {min_silence}s")
        
        try:
            # Run FFmpeg and capture stderr (where silencedetect outputs its data)
            process = subprocess.Popen(
                cmd, 
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # Parse silence detection output
            for line in process.stderr:
                line = line.strip()
                
                # Parse silence_start
                start_match = re.search(r'silence_start:\s*([0-9]+(?:\.[0-9]+)?)', line)
                if start_match:
                    continue
                
                # Parse silence_end and duration
                end_match = re.search(
                    r'silence_end:\s*([0-9]+(?:\.[0-9]+)?)\s*\|\s*silence_duration:\s*([0-9]+(?:\.[0-9]+)?)', 
                    line
                )
                if end_match:
                    end_time = float(end_match.group(1))
                    duration = float(end_match.group(2))
                    
                    # Calculate start time from end and duration
                    start_time = end_time - duration
                    
                    silence = SilenceSegment(
                        start=start_time,
                        end=end_time,
                        duration=duration
                    )
                    silences.append(silence)
            
            process.wait()
            
            self.logger.info(f"Detected {len(silences)} silence segments")
            return silences
            
        except Exception as e:
            self.logger.error(f"Error detecting silences: {e}")
            return []
    
    def calculate_adaptive_threshold(self, silences: List[SilenceSegment]) -> float:
        """Calculate adaptive threshold using quartile method to handle outliers."""
        if not silences:
            detection_config = self.config.get('detection', {})
            return detection_config.get('min_silence', 1.0)
        
        # 提取所有静音时长并排序
        durations = [seg.duration for seg in silences]
        durations.sort()
        
        n = len(durations)
        
        # 如果静音段太少，使用中位数
        if n < 4:
            median = durations[n // 2]
            self.logger.info(f"Too few silences ({n}), using median: {median:.2f}s")
            reference_duration = median
        else:
            # 计算四分位数
            q1_idx = n // 4
            q3_idx = 3 * n // 4
            
            q1 = durations[q1_idx]  # 第一四分位数
            q3 = durations[q3_idx]  # 第三四分位数
            iqr = q3 - q1  # 四分位距
            
            # 定义异常值边界
            lower_bound = q1 - 1.5 * iqr
            upper_bound = q3 + 1.5 * iqr
            
            # 过滤异常值，保留正常范围内的静音段
            normal_durations = [d for d in durations if lower_bound <= d <= upper_bound]
            
            if not normal_durations:
                # 如果没有正常值，使用中位数
                median = durations[n // 2]
                self.logger.info(f"No normal durations found, using median: {median:.2f}s")
                reference_duration = median
            else:
                # 使用正常范围内的最大值作为参考
                reference_duration = max(normal_durations)
                outlier_count = len(durations) - len(normal_durations)
                self.logger.info(f"Quartile analysis: Q1={q1:.2f}s, Q3={q3:.2f}s, IQR={iqr:.2f}s")
                self.logger.info(f"Normal range: {lower_bound:.2f}s - {upper_bound:.2f}s")
                self.logger.info(f"Using max of normal range: {reference_duration:.2f}s (filtered {outlier_count} outliers)")
        
        # 获取配置参数
        detection_config = self.config.get('detection', {})
        min_silence = detection_config.get('min_silence', 1.0)
        adaptive_config = self.config.get('adaptive', {})
        adaptive_ratio = adaptive_config.get('adaptive_ratio', 0.7)
        
        # 验证 adaptive_ratio (0-1)
        adaptive_ratio = max(0.0, min(1.0, adaptive_ratio))
        
        # 计算自适应阈值: max(min_silence, reference_duration * adaptive_ratio)
        adaptive_threshold = max(min_silence, reference_duration * adaptive_ratio)
        
        self.logger.info(f"Adaptive threshold: {adaptive_threshold:.2f}s (reference: {reference_duration:.2f}s, ratio: {adaptive_ratio})")
        return adaptive_threshold
    
    def generate_chapter_marks(self, silences: List[SilenceSegment], duration: float) -> List[ChapterMark]:
        """Generate chapter marks from silence segments."""
        if not silences:
            self.logger.warning("No silence segments detected")
            chapters_config = self.config.get('chapters', {})
            prefix = chapters_config.get('prefix', 'Chapter')
            start_index = chapters_config.get('start_index', 1)
            return [ChapterMark(0.0, f"{prefix} {start_index}", start_index)]
        
        # Get configuration parameters
        detection_config = self.config.get('detection', {})
        adaptive_config = self.config.get('adaptive', {})
        chapters_config = self.config.get('chapters', {})
        
        # Calculate adaptive threshold if enabled
        if adaptive_config.get('enabled', True):
            effective_min_silence = self.calculate_adaptive_threshold(silences)
        else:
            effective_min_silence = detection_config.get('min_silence', 1.0)
        
        # Filter silences based on effective threshold
        valid_silences = [
            seg for seg in silences 
            if seg.duration >= effective_min_silence
        ]
        
        self.logger.info(f"Valid silences after filtering: {len(valid_silences)}")
        
        # Generate candidate chapter times
        candidates = []
        safety_ratio = detection_config.get('safety_ratio', 0.10)
        skip_head = detection_config.get('skip_head', 2.0)
        skip_tail = detection_config.get('skip_tail', 2.0)
        
        for seg in valid_silences:
            # Calculate chapter time: silence_end - safety_ratio * silence_duration
            chapter_time = seg.end - (safety_ratio * seg.duration)
            
            # Apply bounds
            if (chapter_time >= skip_head and 
                chapter_time <= (duration - skip_tail)):
                candidates.append(chapter_time)
        
        # Sort and deduplicate candidates
        candidates.sort()
        
        # Apply minimum gap between chapters
        min_gap = detection_config.get('min_gap', 5.0)
        marks = [0.0]  # Always start with 0
        for candidate in candidates:
            if candidate - marks[-1] >= min_gap:
                marks.append(candidate)
        
        # Convert to ChapterMark objects
        prefix = chapters_config.get('prefix', 'Chapter')
        start_index = chapters_config.get('start_index', 1)
        
        chapters = []
        for i, time in enumerate(marks, start=start_index):
            title = f"{prefix} {i}"
            chapters.append(ChapterMark(time, title, i))
        
        self.logger.info(f"Generated {len(chapters)} chapter marks")
        return chapters
    
    def format_time(self, seconds: float) -> str:
        """Format time as MM:SS.mmm."""
        if seconds < 0:
            seconds = 0
        
        total_ms = int(seconds * 1000 + 0.5)
        mm = total_ms // 60000
        ss = (total_ms % 60000) // 1000
        ms = total_ms % 1000
        
        return f"{mm:02d}:{ss:02d}.{ms:03d}"
    
    def write_chapter_file(self, chapters: List[ChapterMark], output_path: str) -> bool:
        """Write chapter marks to file."""
        try:
            output_config = self.config.get('output', {})
            encoding = output_config.get('encoding', 'utf-8')
            
            lines = []
            for chapter in chapters:
                time_str = self.format_time(chapter.time)
                lines.append(f"{time_str} {chapter.title}")
            
            content = '\n'.join(lines)
            
            with open(output_path, 'w', encoding=encoding) as f:
                f.write(content)
            
            self.logger.info(f"Chapter file written: {output_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error writing chapter file: {e}")
            return False
    
    def process_video(self, video_path: str) -> bool:
        """Process a single video file."""
        video_path = Path(video_path)
        
        if not video_path.exists():
            self.logger.error(f"Video file not found: {video_path}")
            return False
        
        self.logger.info(f"Processing video: {video_path.name}")
        
        # Get video duration
        duration = self.get_video_duration(str(video_path))
        if duration is None:
            return False
        
        # Detect silences
        silences = self.detect_silences(str(video_path))
        if not silences:
            self.logger.warning("No silences detected")
        
        # Generate chapter marks
        chapters = self.generate_chapter_marks(silences, duration)
        
        # Determine output path
        output_config = self.config.get('output', {})
        suffix = output_config.get('suffix', '.chapter')
        output_path = video_path.with_suffix(suffix)
        
        # Write chapter file
        success = self.write_chapter_file(chapters, str(output_path))
        
        if success:
            self.logger.info(f"Successfully processed: {video_path.name}")
            self.logger.info(f"Generated {len(chapters)} chapters")
            for chapter in chapters:
                self.logger.info(f"  {self.format_time(chapter.time)} - {chapter.title}")
        
        return success
    
    def process_directory(self) -> int:
        """Process all video files in the configured directory."""
        input_config = self.config.get('input', {})
        path = input_config.get('path', '.')
        pattern = input_config.get('pattern', '*.mp4')
        
        directory = Path(path)
        
        if not directory.exists() or not directory.is_dir():
            self.logger.error(f"Directory not found: {directory}")
            return 0
        
        # Handle multiple formats with curly braces
        if '{' in pattern and '}' in pattern:
            # Extract formats from pattern like "*.{mp4,mkv,avi}"
            start = pattern.find('{')
            end = pattern.find('}')
            if start != -1 and end != -1:
                prefix = pattern[:start]
                suffix = pattern[end+1:]
                formats = pattern[start+1:end].split(',')
                
                video_files = []
                for fmt in formats:
                    fmt_pattern = prefix + fmt.strip() + suffix
                    video_files.extend(directory.glob(fmt_pattern))
            else:
                video_files = list(directory.glob(pattern))
        else:
            video_files = list(directory.glob(pattern))
        
        if not video_files:
            self.logger.warning(f"No video files found in {directory} matching pattern: {pattern}")
            return 0
        
        self.logger.info(f"Found {len(video_files)} video files to process")
        
        success_count = 0
        total_files = len(video_files)
        
        for i, video_file in enumerate(video_files, 1):
            try:
                if self.config.get('logging', {}).get('show_progress', True):
                    self.logger.info(f"Processing {i}/{total_files}: {video_file.name}")
                
                if self.process_video(str(video_file)):
                    success_count += 1
            except Exception as e:
                self.logger.error(f"Error processing {video_file.name}: {e}")
        
        self.logger.info(f"Successfully processed {success_count}/{total_files} files")
        return success_count

def load_config() -> Dict[str, Any]:
    """Load configuration from config.json file."""
    config_path = Path('config.json')
    
    if not config_path.exists():
        print("Error: config.json not found!")
        print("Please create a config.json file with your settings.")
        sys.exit(1)
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        return config
    except Exception as e:
        print(f"Error loading config.json: {e}")
        sys.exit(1)

def main():
    """Main entry point."""
    print("MPVChapter - Automatic Video Chapter Extraction")
    print("=" * 50)
    
    # Load configuration
    config = load_config()
    
    # Create extractor and process
    try:
        extractor = VideoChapterExtractor(config)
        
        # Check if batch mode is enabled
        input_config = config.get('input', {})
        batch_mode = input_config.get('batch_mode', True)
        
        if batch_mode:
            # Batch processing
            success_count = extractor.process_directory()
            if success_count > 0:
                print(f"\n✅ Successfully processed {success_count} video files!")
            else:
                print("\n❌ No files were processed successfully.")
                sys.exit(1)
        else:
            # Single file processing
            path = input_config.get('path', '.')
            pattern = input_config.get('pattern', '*.mp4')
            
            directory = Path(path)
            
            if not directory.exists() or not directory.is_dir():
                print(f"Directory not found: {directory}")
                sys.exit(1)
            
            # Handle multiple formats with curly braces
            if '{' in pattern and '}' in pattern:
                # Extract formats from pattern like "*.{mp4,mkv,avi}"
                start = pattern.find('{')
                end = pattern.find('}')
                if start != -1 and end != -1:
                    prefix = pattern[:start]
                    suffix = pattern[end+1:]
                    formats = pattern[start+1:end].split(',')
                    
                    video_files = []
                    for fmt in formats:
                        fmt_pattern = prefix + fmt.strip() + suffix
                        video_files.extend(directory.glob(fmt_pattern))
                else:
                    video_files = list(directory.glob(pattern))
            else:
                video_files = list(directory.glob(pattern))
            
            if not video_files:
                print(f"No video files found matching pattern: {pattern}")
                sys.exit(1)
            
            # Process first file only
            success = extractor.process_video(str(video_files[0]))
            if success:
                print(f"\n✅ Successfully processed: {video_files[0].name}")
            else:
                print(f"\n❌ Failed to process: {video_files[0].name}")
                sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n⏹️  Processing interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main() 