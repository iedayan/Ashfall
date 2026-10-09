import traceback
import sys
import os
sys.path.insert(0, '.')

# Force loguru to show tracebacks for all loggers
import loguru
loguru.logger.remove()
loguru.logger.add(sys.stderr, level="TRACE", backtrace=True, diagnose=True)

# Also patch the logger in the cli module
from data_process.rig_preprocess import cli as cli_module
cli_module.logger.remove()
cli_module.logger.add(sys.stderr, level="TRACE", backtrace=True, diagnose=True)

# Don't catch - let exception propagate for full traceback
from data_process.rig_preprocess.cli import main
sys.argv = ['rig_preprocess', 'run',
    '--input', os.environ['ASSET_PATH'],
    '--output_dir', os.environ['OUTPUT_DIR'],
    '--annotate', 'rule', '--no_review', '--save_clips']
sys.exit(main())