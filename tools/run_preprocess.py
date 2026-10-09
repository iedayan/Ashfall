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

print("=== Starting rig_preprocess ===", file=sys.stderr)
print(f"ASSET_PATH={os.environ.get('ASSET_PATH')}", file=sys.stderr)
print(f"OUTPUT_DIR={os.environ.get('OUTPUT_DIR')}", file=sys.stderr)

# Test bpy import
print("=== Testing bpy import ===", file=sys.stderr)
try:
    import bpy
    print(f"bpy version: {bpy.app.version_string}", file=sys.stderr)
except Exception as e:
    print(f"bpy import failed: {e}", file=sys.stderr)
    traceback.print_exc()

print("=== Calling main ===", file=sys.stderr)

try:
    from data_process.rig_preprocess.cli import main
    sys.argv = ['rig_preprocess', 'run',
        '--input', os.environ['ASSET_PATH'],
        '--output_dir', os.environ['OUTPUT_DIR'],
        '--annotate', 'rule', '--no_review', '--save_clips']
    sys.exit(main())
except Exception as e:
    print(f"=== EXCEPTION CAUGHT ===", file=sys.stderr)
    print(f"Exception type: {type(e).__name__}", file=sys.stderr)
    print(f"Exception message: {e}", file=sys.stderr)
    traceback.print_exc()
    sys.exit(1)