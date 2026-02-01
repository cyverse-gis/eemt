#!/usr/bin/env python3
"""
Container wrapper for EEMT Solar Radiation Workflow
Executes sol/run-workflow within the Docker container environment
"""

import os
import sys
import json
import argparse
import subprocess
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description='Run EEMT Solar Radiation Workflow in Container')
    parser.add_argument('--dem', required=True, help='Path to DEM file within container')
    parser.add_argument('--output', required=True, help='Output directory within container')
    parser.add_argument('--step', type=float, default=15.0, help='Time step in minutes')
    parser.add_argument('--linke-value', type=float, default=3.0, help='Linke turbidity value')
    parser.add_argument('--albedo-value', type=float, default=0.2, help='Surface albedo value')
    parser.add_argument('--num-threads', type=int, default=4, help='Number of processing threads')
    parser.add_argument('--job-id', required=True, help='Job ID for tracking')
    
    args = parser.parse_args()
    
    logger.info(f"Starting solar workflow for job {args.job_id}")
    logger.info(f"DEM: {args.dem}")
    logger.info(f"Output: {args.output}")
    logger.info(f"Parameters: step={args.step}, linke={args.linke_value}, albedo={args.albedo_value}, threads={args.num_threads}")
    
    # Set up environment
    os.environ['GRASS_BATCH_JOB'] = 'true'
    os.environ['GRASS_MESSAGE_FORMAT'] = 'plain'
    
    # Verify input file exists
    if not os.path.exists(args.dem):
        logger.error(f"DEM file not found: {args.dem}")
        return 1
    
    # Create output directory
    output_path = Path(args.output)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Change to temporary working directory
    work_dir = Path("/tmp") / f"solar_work_{args.job_id}"
    work_dir.mkdir(exist_ok=True)
    os.chdir(work_dir)
    
    # Copy DEM to working directory  
    dem_name = Path(args.dem).name
    subprocess.run(['cp', args.dem, str(work_dir / dem_name)], check=True)
    
    # Build command for original sol/run-workflow
    cmd = [
        'python', '/opt/eemt/sol/sol/run-workflow',
        '--step', str(args.step),
        '--linke_value', str(args.linke_value), 
        '--albedo_value', str(args.albedo_value),
        '--num_threads', str(args.num_threads),
        '-O', str(output_path),
        dem_name
    ]
    
    logger.info(f"Executing: {' '.join(cmd)}")
    
    try:
        # Run the workflow with real-time output
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )
        
        # Stream output for progress monitoring
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                print(output.strip(), flush=True)
                
        # Get return code
        return_code = process.poll()
        
        if return_code == 0:
            logger.info(f"Solar workflow completed successfully for job {args.job_id}")
            print("workflow completed successfully")
        else:
            logger.error(f"Solar workflow failed with return code {return_code}")
            return return_code
            
    except Exception as e:
        logger.error(f"Error executing solar workflow: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())