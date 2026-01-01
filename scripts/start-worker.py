#!/usr/bin/env python3
"""
EEMT Worker Node Startup Script
Starts a worker node and connects to EEMT master for distributed workflow execution
"""

import sys
import argparse
import logging
import socket
import subprocess
from pathlib import Path

# Add web-interface to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "web-interface"))

from containers.workflow_manager import DistributedWorkflowManager, NodeType, WorkerConfig, ContainerConfig

def detect_resources():
    """Detect available system resources"""
    import os
    import shutil
    
    # Detect CPU cores
    cpu_cores = os.cpu_count() or 4
    
    # Detect memory (in GB)
    try:
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith('MemTotal:'):
                    # Convert from KB to GB
                    memory_kb = int(line.split()[1])
                    memory_gb = max(1, memory_kb // (1024 * 1024))
                    break
            else:
                memory_gb = 8  # Default fallback
    except:
        memory_gb = 8
    
    # Detect disk space (in GB) 
    try:
        disk_usage = shutil.disk_usage('/')
        disk_gb = max(10, disk_usage.free // (1024 * 1024 * 1024))
    except:
        disk_gb = 50
    
    return cpu_cores, memory_gb, disk_gb

def check_master_connectivity(master_host, master_port, timeout=10):
    """Check if master is accessible"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((master_host, master_port))
        sock.close()
        return result == 0
    except:
        return False

def check_cctools_available():
    """Check if CCTools (work_queue_worker) is available"""
    try:
        result = subprocess.run(['work_queue_worker', '--version'], 
                              capture_output=True, timeout=5)
        return result.returncode == 0
    except:
        return False

def main():
    parser = argparse.ArgumentParser(description="Start EEMT Worker Node")
    parser.add_argument("--master-host", "-m", type=str, required=True,
                       help="Master node hostname or IP address")
    parser.add_argument("--master-port", "-p", type=int, default=9123,
                       help="Master node port (default: 9123)")
    parser.add_argument("--work-dir", "-w", type=str, default="./eemt-worker",
                       help="Working directory for worker node")
    parser.add_argument("--cores", "-c", type=int,
                       help="Number of CPU cores (auto-detected if not specified)")
    parser.add_argument("--memory", type=str,
                       help="Memory limit (e.g., '8G', auto-detected if not specified)")
    parser.add_argument("--disk", type=str,
                       help="Disk limit (e.g., '50G', auto-detected if not specified)")
    parser.add_argument("--reconnect-attempts", type=int, default=5,
                       help="Reconnection attempts if connection fails (default: 5)")
    parser.add_argument("--reconnect-delay", type=int, default=10,
                       help="Delay between reconnection attempts in seconds (default: 10)")
    parser.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], 
                       default="INFO", help="Logging level")
    parser.add_argument("--container-mode", action="store_true",
                       help="Run worker in container mode (requires Docker)")
    parser.add_argument("--dry-run", action="store_true",
                       help="Show configuration and exit without starting worker")
    
    args = parser.parse_args()
    
    # Configure logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger("eemt-worker")
    
    # Detect system resources
    detected_cores, detected_memory, detected_disk = detect_resources()
    
    cores = args.cores or detected_cores
    memory = args.memory or f"{detected_memory}G"
    disk = args.disk or f"{detected_disk}G"
    
    logger.info(f"Starting EEMT Worker Node")
    logger.info(f"Master: {args.master_host}:{args.master_port}")
    logger.info(f"Resources: {cores} cores, {memory} memory, {disk} disk")
    logger.info(f"Work directory: {Path(args.work_dir).absolute()}")
    
    # Check prerequisites
    if not check_cctools_available():
        logger.error("CCTools (work_queue_worker) not found. Please install CCTools.")
        logger.error("Installation: https://cctools.readthedocs.io/")
        return 1
    
    # Check master connectivity
    logger.info("Checking master connectivity...")
    if not check_master_connectivity(args.master_host, args.master_port):
        logger.warning(f"Cannot connect to master at {args.master_host}:{args.master_port}")
        logger.warning("Worker will attempt to connect when master becomes available")
    else:
        logger.info("Master is accessible")
    
    # Create working directory
    work_dir = Path(args.work_dir)
    work_dir.mkdir(exist_ok=True, parents=True)
    
    # Configure worker
    worker_config = WorkerConfig(
        master_host=args.master_host,
        master_port=args.master_port,
        worker_cores=cores,
        worker_memory=memory,
        worker_disk=disk,
        reconnect_attempts=args.reconnect_attempts,
        reconnect_delay=args.reconnect_delay
    )
    
    if args.dry_run:
        print(f"""
EEMT Worker Configuration:
  Master: {args.master_host}:{args.master_port}
  Cores: {cores}
  Memory: {memory}
  Disk: {disk}
  Work Directory: {work_dir.absolute()}
  Container Mode: {'Yes' if args.container_mode else 'No'}
  Reconnect: {args.reconnect_attempts} attempts, {args.reconnect_delay}s delay

Command that would be executed:
  work_queue_worker {args.master_host}:{args.master_port} --cores {cores} --memory {memory} --disk {disk} --timeout 3600 --debug all
""")
        return 0
    
    try:
        # Initialize worker
        worker = DistributedWorkflowManager(
            base_dir=work_dir,
            node_type=NodeType.WORKER,
            worker_config=worker_config
        )
        
        # Start worker node
        if not worker.start_worker_node():
            logger.error("Failed to start worker node")
            return 1
        
        logger.info("Worker node started successfully")
        
        print(f"""
EEMT Worker Node Started Successfully!

Configuration:
  Master: {args.master_host}:{args.master_port}
  Cores: {cores}
  Memory: {memory}
  Disk: {disk}
  Work Directory: {work_dir.absolute()}

Press Ctrl+C to stop the worker node.
""")
        
        # Keep worker running
        try:
            while True:
                import time
                time.sleep(30)
                
                # Display periodic status
                status = worker.get_cluster_status()
                if status.get("worker_processes", 0) > 0:
                    logger.info(f"Worker status: {status['worker_processes']} processes running")
                else:
                    logger.warning("No worker processes active, attempting reconnection...")
                    worker.start_worker_node()
                
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
        
        # Cleanup
        worker.stop_worker_nodes()
        logger.info("Worker node stopped")
        return 0
        
    except Exception as e:
        logger.error(f"Worker node error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())