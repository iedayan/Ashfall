import traceback
import sys
import os
sys.path.insert(0, '.')

# Set loguru to trace level for more verbose output
import loguru
loguru.logger.remove()
loguru.logger.add(sys.stderr, level="TRACE")

try:
    from data_process.rig_preprocess.cli import main
    sys.argv = ['rig_preprocess', 'run',
        '--input', os.environ['ASSET_PATH'],
        '--output_dir', os.environ['OUTPUT_DIR'],
        '--annotate', 'rule', '--no_review', '--save_clips']
    sys.exit(main())
except Exception as e:
    traceback.print_exc()
    sys.exit(1)