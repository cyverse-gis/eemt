#!/usr/bin/env python3
"""
EEMT Master Node Startup Script
Starts a master/foreman node for distributed EEMT workflow execution
"""

import sys
import argparse
import logging
from pathlib import Path

# Add web-interface to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "web-interface"))

from containers.workflow_manager import DistributedWorkflowManager, NodeType, MasterConfig, ContainerConfig

def main():
    parser = argparse.ArgumentParser(description="Start EEMT Master Node")
    parser.add_argument("--work-dir", "-w", type=str, default="./eemt-master",
                       help="Working directory for master node")
    parser.add_argument("--port", "-p", type=int, default=9123,
                       help="Work Queue master port (default: 9123)")
    parser.add_argument("--project", type=str, default="EEMT",
                       help="Work Queue project name (default: EEMT)")
    parser.add_argument("--max-workers", type=int, default=100,
                       help="Maximum number of workers (default: 100)")
    parser.add_argument("--password", type=str,
                       help="Work Queue password (auto-generated if not provided)")
    parser.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], 
                       default="INFO", help="Logging level")
    parser.add_argument("--web-interface", action="store_true",
                       help="Also start FastAPI web interface")
    parser.add_argument("--web-port", type=int, default=5000,
                       help="Web interface port (default: 5000)")
    
    args = parser.parse_args()
    
    # Configure logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger("eemt-master")
    
    # Create working directory
    work_dir = Path(args.work_dir)
    work_dir.mkdir(exist_ok=True, parents=True)
    
    logger.info(f"Starting EEMT Master Node")
    logger.info(f"Work directory: {work_dir.absolute()}")
    logger.info(f"Port: {args.port}")
    logger.info(f"Project: {args.project}")
    logger.info(f"Max workers: {args.max_workers}")
    
    # Configure master
    master_config = MasterConfig(
        port=args.port,
        max_workers=args.max_workers,
        work_queue_project=args.project,
        work_queue_password=args.password
    )
    
    try:
        # Initialize master workflow manager
        master = DistributedWorkflowManager(
            base_dir=work_dir,
            node_type=NodeType.MASTER,
            master_config=master_config
        )
        
        # Start master node
        if not master.start_master_node():
            logger.error("Failed to start master node")
            return 1
        
        logger.info("Master node started successfully")
        logger.info(f"Workers can connect to: {master.get_local_ip()}:{args.port}")
        logger.info(f"Project name: {args.project}")
        
        # Optionally start web interface
        if args.web_interface:
            logger.info(f"Starting web interface on port {args.web_port}")
            import uvicorn
            from app import app
            
            # Start web interface in separate thread
            import threading
            web_thread = threading.Thread(
                target=lambda: uvicorn.run(app, host="0.0.0.0", port=args.web_port, log_level=args.log_level.lower()),
                daemon=True
            )
            web_thread.start()
            logger.info(f"Web interface available at: http://0.0.0.0:{args.web_port}")
        
        # Display connection information
        print(f"""
EEMT Master Node Started Successfully!

Connection Information:
  Master Host: {master.get_local_ip()}
  Master Port: {args.port}
  Project Name: {args.project}
  
Workers can connect using:
  python start-worker.py --master-host {master.get_local_ip()} --master-port {args.port}

Monitor status:
  work_queue_status -M {args.project}
        
Press Ctrl+C to stop the master node.
""")
        
        # Keep master running
        try:
            while True:
                import time
                time.sleep(30)
                
                # Display periodic status
                status = master.get_cluster_status()
                logger.info(f"Master status: {status['total_workers']} workers, "
                           f"{status['tasks_running']} running, {status['tasks_waiting']} waiting")
                
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
        
        # Cleanup
        master.stop_master_node()
        logger.info("Master node stopped")
        return 0

    except Exception as e:
        logger.error(f"Master node error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())