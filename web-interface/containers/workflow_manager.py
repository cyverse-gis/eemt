#!/usr/bin/env python3
"""
EEMT Distributed Workflow Manager
Supports master/worker architecture for distributed EEMT execution across VMs, HPC, and HTC systems
"""

import os
import json
import time
import socket
import docker
import asyncio
import logging
import subprocess
from pathlib import Path
from typing import Dict, Optional, AsyncGenerator, List
from dataclasses import dataclass
from enum import Enum
import threading
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class NodeType(Enum):
    """Node execution types"""
    LOCAL = "local"          # Single-node local execution
    MASTER = "master"        # Master/foreman node
    WORKER = "worker"        # Worker node

@dataclass
class ContainerConfig:
    """Container execution configuration"""
    image: str = "eemt:ubuntu24.04"
    cpu_limit: str = "4"
    memory_limit: str = "8G"
    disk_limit: str = "50G"
    remove_after: bool = True
    network_mode: str = "bridge"

@dataclass
class MasterConfig:
    """Master node configuration"""
    port: int = 9123
    max_workers: int = 100
    worker_timeout: int = 300
    heartbeat_interval: int = 30
    work_queue_project: str = "EEMT"
    work_queue_password: Optional[str] = None

@dataclass
class WorkerConfig:
    """Worker node configuration"""
    master_host: str = "localhost"
    master_port: int = 9123
    worker_cores: int = 4
    worker_memory: str = "8G"
    worker_disk: str = "50G"
    reconnect_attempts: int = 5
    reconnect_delay: int = 10

class DistributedWorkflowManager:
    """Manages distributed EEMT workflow execution across multiple nodes"""
    
    def __init__(
        self, 
        base_dir: Path, 
        node_type: NodeType = NodeType.LOCAL,
        container_config: Optional[ContainerConfig] = None,
        master_config: Optional[MasterConfig] = None,
        worker_config: Optional[WorkerConfig] = None
    ):
        self.base_dir = Path(base_dir)
        self.node_type = node_type
        self.container_config = container_config or ContainerConfig()
        self.master_config = master_config or MasterConfig()
        self.worker_config = worker_config or WorkerConfig()
        
        # Directory structure
        self.uploads_dir = self.base_dir / "uploads"
        self.results_dir = self.base_dir / "results"
        self.temp_dir = self.base_dir / "temp"
        self.cache_dir = self.base_dir / "cache"
        self.shared_dir = self.base_dir / "shared"  # For distributed file sharing
        
        # Ensure directories exist
        for dir_path in [self.uploads_dir, self.results_dir, self.temp_dir, self.cache_dir, self.shared_dir]:
            dir_path.mkdir(exist_ok=True, parents=True)
        
        # Initialize based on node type
        self.makeflow_process = None
        self.worker_processes = {}
        self.active_workers = {}
        
        if node_type in [NodeType.LOCAL, NodeType.MASTER]:
            # Initialize Docker client with proper error handling
            self.docker_client = None
            self.docker_available = False
            
            # First, try subprocess mode as it's most reliable
            try:
                import subprocess
                logger.info("Testing Docker via subprocess...")
                result = subprocess.run(['docker', 'version', '--format', 'json'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    logger.info("Docker CLI accessible via subprocess - using subprocess mode")
                    self.docker_client = "subprocess"  # Mark as subprocess mode
                    self.docker_available = True
                else:
                    raise Exception(f"Docker CLI returned code {result.returncode}")
            except Exception as e:
                logger.warning(f"Docker subprocess test failed: {e}")
                
                # Try Python Docker SDK as fallback
                try:
                    # Try with default environment
                    self.docker_client = docker.from_env(timeout=10)
                    self.docker_client.ping()
                    logger.info("Docker client initialized with Python SDK")
                    self.docker_available = True
                except docker.errors.DockerException as de:
                    logger.warning(f"Docker Python SDK failed: {de}")
                    # Try direct socket connection
                    try:
                        self.docker_client = docker.DockerClient(base_url='unix://var/run/docker.sock', timeout=10)
                        self.docker_client.ping()
                        logger.info("Docker client initialized with direct socket")
                        self.docker_available = True
                    except Exception as e2:
                        logger.warning(f"Docker socket connection failed: {e2}")
                        logger.info("Running in mock mode for testing - Docker not available")
                        self.docker_client = None
                        self.docker_available = False
        else:
            # Worker nodes don't need Docker client
            self.docker_client = None
            self.docker_available = False
        
        logger.info(f"Initialized {node_type.value} workflow manager")
    
    def check_docker_availability(self) -> bool:
        """Check if Docker is available for container execution"""
        return hasattr(self, 'docker_available') and self.docker_available
    
    def start_master_node(self) -> bool:
        """Start master node with Work Queue foreman"""
        if self.node_type != NodeType.MASTER:
            logger.error("Cannot start master node: not configured as master")
            return False
        
        try:
            # Ensure work queue password exists
            password_file = Path.home() / ".eemt-makeflow-password"
            if not password_file.exists():
                # Generate random password if none exists
                import secrets
                password = secrets.token_hex(16)
                with open(password_file, 'w') as f:
                    f.write(password)
                logger.info(f"Generated Work Queue password: {password_file}")
                self.master_config.work_queue_password = password
            else:
                with open(password_file, 'r') as f:
                    self.master_config.work_queue_password = f.read().strip()
            
            logger.info(f"Starting master node on port {self.master_config.port}")
            logger.info(f"Project name: {self.master_config.work_queue_project}")
            logger.info(f"Max workers: {self.master_config.max_workers}")
            
            # Start monitoring thread for worker status
            monitor_thread = threading.Thread(target=self._monitor_workers, daemon=True)
            monitor_thread.start()
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to start master node: {e}")
            return False
    
    def start_worker_node(self) -> bool:
        """Start worker node and connect to master"""
        if self.node_type != NodeType.WORKER:
            logger.error("Cannot start worker node: not configured as worker")
            return False
        
        try:
            logger.info(f"Starting worker node")
            logger.info(f"Master: {self.worker_config.master_host}:{self.worker_config.master_port}")
            logger.info(f"Resources: {self.worker_config.worker_cores} cores, {self.worker_config.worker_memory} memory")
            
            # Build work queue worker command
            cmd = [
                "work_queue_worker",
                f"{self.worker_config.master_host}:{self.worker_config.master_port}",
                "--cores", str(self.worker_config.worker_cores),
                "--memory", self.worker_config.worker_memory,
                "--disk", self.worker_config.worker_disk,
                "--timeout", "3600",
                "--debug", "all"
            ]
            
            # Start worker process
            worker_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True
            )
            
            self.worker_processes[worker_process.pid] = worker_process
            logger.info(f"Started worker process {worker_process.pid}")
            
            # Monitor worker in separate thread
            worker_thread = threading.Thread(
                target=self._monitor_worker_process,
                args=(worker_process,),
                daemon=True
            )
            worker_thread.start()
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to start worker node: {e}")
            return False
    
    def _monitor_workers(self):
        """Monitor worker status and connection health"""
        while True:
            try:
                # Get worker status from work queue
                if hasattr(self, 'makeflow_process') and self.makeflow_process:
                    cmd = ["work_queue_status", "-M", self.master_config.work_queue_project]
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        # Parse worker status
                        lines = result.stdout.strip().split('\n')
                        for line in lines[1:]:  # Skip header
                            if line:
                                parts = line.split()
                                if len(parts) >= 8:
                                    project = parts[0]
                                    workers = int(parts[7])
                                    logger.debug(f"Project {project}: {workers} workers connected")
                                    
                time.sleep(self.master_config.heartbeat_interval)
                
            except Exception as e:
                logger.warning(f"Worker monitoring error: {e}")
                time.sleep(self.master_config.heartbeat_interval)
    
    def _monitor_worker_process(self, process):
        """Monitor individual worker process"""
        try:
            for line in process.stdout:
                logger.info(f"Worker {process.pid}: {line.strip()}")
            
            # Process finished
            return_code = process.wait()
            logger.info(f"Worker {process.pid} finished with code {return_code}")
            
            # Remove from active processes
            if process.pid in self.worker_processes:
                del self.worker_processes[process.pid]
                
            # Attempt reconnection if configured
            if return_code != 0 and self.worker_config.reconnect_attempts > 0:
                logger.info(f"Attempting to reconnect worker in {self.worker_config.reconnect_delay} seconds")
                time.sleep(self.worker_config.reconnect_delay)
                self.start_worker_node()
                
        except Exception as e:
            logger.error(f"Worker monitoring error: {e}")
    
    def stop_master_node(self):
        """Stop master node and clean up"""
        if self.makeflow_process:
            logger.info("Stopping master node...")
            self.makeflow_process.terminate()
            try:
                self.makeflow_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.makeflow_process.kill()
            self.makeflow_process = None
    
    def stop_worker_nodes(self):
        """Stop all worker processes"""
        logger.info("Stopping worker nodes...")
        for pid, process in list(self.worker_processes.items()):
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
        self.worker_processes.clear()
    
    def get_cluster_status(self) -> Dict:
        """Get status of distributed cluster"""
        try:
            if self.node_type == NodeType.MASTER:
                cmd = ["work_queue_status", "-M", self.master_config.work_queue_project]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')
                    status = {
                        "node_type": self.node_type.value,
                        "project": self.master_config.work_queue_project,
                        "workers": [],
                        "total_workers": 0,
                        "total_cores": 0,
                        "tasks_waiting": 0,
                        "tasks_running": 0
                    }
                    
                    for line in lines[1:]:  # Skip header
                        if line:
                            parts = line.split()
                            if len(parts) >= 8:
                                status["workers"].append({
                                    "project": parts[0],
                                    "waiting": int(parts[4]),
                                    "running": int(parts[5]),
                                    "complete": int(parts[6]),
                                    "workers": int(parts[7]),
                                    "cores": int(parts[8]) if len(parts) > 8 else 0
                                })
                                status["total_workers"] += int(parts[7])
                                status["tasks_waiting"] += int(parts[4])
                                status["tasks_running"] += int(parts[5])
                    
                    return status
            
            elif self.node_type == NodeType.WORKER:
                return {
                    "node_type": self.node_type.value,
                    "master_host": self.worker_config.master_host,
                    "master_port": self.worker_config.master_port,
                    "worker_processes": len(self.worker_processes),
                    "cores": self.worker_config.worker_cores,
                    "memory": self.worker_config.worker_memory
                }
            
        except Exception as e:
            logger.error(f"Error getting cluster status: {e}")
        
        return {
            "node_type": self.node_type.value,
            "status": "unknown",
            "error": "Unable to get cluster status"
        }

class WorkflowManager(DistributedWorkflowManager):
    """Backward compatibility wrapper for local execution"""
    
    def __init__(self, base_dir: Path, node_type: NodeType = NodeType.LOCAL, config: Optional[ContainerConfig] = None):
        super().__init__(base_dir, node_type, container_config=config)
        self.active_containers = {}  # job_id -> container object mapping
    
    def check_docker_availability(self) -> bool:
        """Check if Docker daemon is available and image exists"""
        if self.docker_client is None:
            return False
            
        # Handle subprocess mode (most reliable)
        if self.docker_client == "subprocess":
            try:
                # Test Docker via subprocess
                import subprocess
                result = subprocess.run(['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    images = result.stdout.strip().split('\n')
                    # Check for the image
                    image_found = any(self.container_config.image in img for img in images)
                    if image_found:
                        logger.debug(f"Docker image {self.container_config.image} found")
                        return True
                    else:
                        logger.warning(f"Docker image {self.container_config.image} not found")
                        logger.info("Please build the image first:")
                        logger.info(f"cd docker/ubuntu/24.04 && ./build.sh")
                        return False
                else:
                    logger.warning(f"Docker command failed with code {result.returncode}")
                    return False
            except subprocess.TimeoutExpired:
                logger.error("Docker check timed out")
                return False
            except Exception as e:
                logger.error(f"Docker subprocess check failed: {e}")
                return False
            
        # Handle normal Docker client mode
        try:
            self.docker_client.ping()
            
            # Check if image exists, if not, suggest build
            try:
                self.docker_client.images.get(self.container_config.image)
                return True
            except docker.errors.ImageNotFound:
                logger.warning(f"Docker image {self.container_config.image} not found")
                logger.info("Please build the image first:")
                logger.info(f"cd docker/ubuntu/24.04 && ./build.sh")
                return False
                
        except Exception as e:
            logger.error(f"Docker not available: {e}")
            return False
    
    async def execute_workflow(
        self, 
        job_id: str, 
        workflow_type: str, 
        dem_filename: str, 
        parameters: Dict
    ) -> AsyncGenerator[str, None]:
        """Execute workflow in container and yield progress updates"""
        
        if not self.check_docker_availability():
            # Fall back to mock execution for testing
            logger.warning(f"Docker not available, running mock workflow for job {job_id}")
            async for update in self._execute_mock_workflow(job_id, workflow_type, dem_filename, parameters):
                yield update
            return
        
        # Handle subprocess mode (preferred for reliability)
        if self.docker_client == "subprocess":
            logger.info(f"Executing workflow {job_id} via subprocess Docker")
            async for update in self._execute_subprocess_workflow(job_id, workflow_type, dem_filename, parameters):
                yield update
            return
        
        try:
            # Prepare volume mounts
            volume_mounts = self._prepare_volumes(job_id)
            
            # Build container command
            container_cmd = self._build_container_command(
                workflow_type, dem_filename, parameters, job_id
            )
            
            # Set environment variables
            environment = self._build_environment(parameters)
            
            logger.info(f"Starting container for job {job_id}")
            logger.info(f"Command: {' '.join(container_cmd)}")
            
            # Run container
            container = self.docker_client.containers.run(
                self.container_config.image,
                command=container_cmd,
                volumes=volume_mounts,
                environment=environment,
                detach=True,
                stdout=True,
                stderr=True,
                remove=self.container_config.remove_after,
                network_mode=self.container_config.network_mode,
                cpu_quota=int(self.container_config.cpu_limit) * 100000,  # Convert to microseconds
                mem_limit=self.container_config.memory_limit
            )
            
            # Store container reference for potential cancellation
            self.active_containers[job_id] = container
            
            try:
                # Monitor container execution
                async for progress_update in self._monitor_container(container, job_id):
                    yield progress_update
            finally:
                # Remove container reference when done
                if job_id in self.active_containers:
                    del self.active_containers[job_id]
                
        except docker.errors.ImageNotFound:
            yield "ERROR: Docker image not found. Please build the EEMT container first."
        except docker.errors.ContainerError as e:
            yield f"ERROR: Container execution failed: {e}"
        except Exception as e:
            yield f"ERROR: Unexpected error: {e}"
    
    def _prepare_volumes(self, job_id: str) -> Dict[str, Dict]:
        """Prepare Docker volume mounts for job execution"""
        job_results_dir = self.results_dir / job_id
        job_temp_dir = self.temp_dir / job_id
        
        # Create job-specific directories
        job_results_dir.mkdir(exist_ok=True, parents=True)
        job_temp_dir.mkdir(exist_ok=True, parents=True)
        
        return {
            str(self.uploads_dir): {'bind': '/data/input', 'mode': 'ro'},
            str(job_results_dir): {'bind': '/data/output', 'mode': 'rw'},
            str(job_temp_dir): {'bind': '/data/temp', 'mode': 'rw'},
            str(self.cache_dir): {'bind': '/data/cache', 'mode': 'rw'},
        }
    
    def _build_container_command(
        self, 
        workflow_type: str, 
        dem_filename: str, 
        parameters: Dict, 
        job_id: str
    ) -> list:
        """Build container execution command"""
        
        if workflow_type == "sol":
            return [
                "python", "/opt/eemt/bin/run-solar-workflow.py",
                "--dem", f"/data/input/{dem_filename}",
                "--output", "/data/output",
                "--step", str(parameters["step"]),
                "--linke-value", str(parameters["linke_value"]),
                "--albedo-value", str(parameters["albedo_value"]),
                "--num-threads", str(parameters["num_threads"]),
                "--job-id", job_id
            ]
        elif workflow_type == "eemt":
            return [
                "python", "/opt/eemt/bin/run-eemt-workflow.py",
                "--dem", f"/data/input/{dem_filename}",
                "--output", "/data/output", 
                "--start-year", str(parameters["start_year"]),
                "--end-year", str(parameters["end_year"]),
                "--step", str(parameters["step"]),
                "--linke-value", str(parameters["linke_value"]),
                "--albedo-value", str(parameters["albedo_value"]),
                "--num-threads", str(parameters["num_threads"]),
                "--job-id", job_id
            ]
        else:
            raise ValueError(f"Unknown workflow type: {workflow_type}")
    
    def _build_environment(self, parameters: Dict) -> Dict[str, str]:
        """Build container environment variables"""
        return {
            'EEMT_NUM_THREADS': str(parameters["num_threads"]),
            'EEMT_MEMORY_LIMIT': self.container_config.memory_limit,
            'GRASS_BATCH_JOB': 'true',
            'GRASS_MESSAGE_FORMAT': 'plain',
            'GRASS_VERBOSE': '1',
            'MAKEFLOW_BATCH_TYPE': 'local',
            'MAKEFLOW_MAX_REMOTE_JOBS': str(parameters["num_threads"]),
            'PYTHONUNBUFFERED': '1'  # Ensure immediate log output
        }
    
    async def _monitor_container(self, container, job_id: str) -> AsyncGenerator[str, None]:
        """Monitor container execution and parse progress"""
        try:
            # Initial status
            yield "STATUS: Container started, initializing workflow..."
            
            # Stream container logs
            log_stream = container.logs(stream=True, follow=True)
            
            for log_line in log_stream:
                log_text = log_line.decode('utf-8').strip()
                
                if log_text:
                    logger.info(f"Container {job_id}: {log_text}")
                    
                    # Parse progress from log output
                    progress_info = self._parse_progress(log_text)
                    if progress_info:
                        yield progress_info
                    
                    # Check for completion or error
                    if "workflow completed successfully" in log_text.lower():
                        yield "STATUS: Workflow completed successfully"
                        break
                    elif "error" in log_text.lower() or "failed" in log_text.lower():
                        yield f"ERROR: {log_text}"
                        break
            
            # Wait for container to finish
            result = container.wait()
            exit_code = result['StatusCode']
            
            if exit_code == 0:
                yield "COMPLETED: Workflow execution finished successfully"
            else:
                yield f"FAILED: Container exited with code {exit_code}"
                
        except Exception as e:
            yield f"ERROR: Monitoring failed: {e}"
    
    def _parse_progress(self, log_line: str) -> Optional[str]:
        """Parse progress information from container logs"""
        
        # Look for specific progress indicators
        if "Starting task" in log_line and "/" in log_line:
            # Example: "Starting task 45/365"
            try:
                parts = log_line.split()
                for part in parts:
                    if "/" in part:
                        current, total = part.split("/")
                        progress = int(current) / int(total) * 100
                        return f"PROGRESS: {progress:.1f}% ({current}/{total} tasks)"
            except (ValueError, IndexError):
                pass
        
        # Look for Makeflow progress
        elif "COMPLETED" in log_line and "jobs" in log_line:
            # Example: "COMPLETED 45 jobs"
            try:
                parts = log_line.split()
                if "COMPLETED" in parts:
                    idx = parts.index("COMPLETED")
                    if idx + 1 < len(parts):
                        completed = int(parts[idx + 1])
                        return f"PROGRESS: {completed} tasks completed"
            except (ValueError, IndexError):
                pass
        
        # Look for workflow stages
        elif any(stage in log_line.lower() for stage in [
            "initializing", "processing dem", "running solar calculations", 
            "generating monthly summaries", "calculating eemt"
        ]):
            return f"STATUS: {log_line}"
        
        return None
    
    def cleanup_job_data(self, job_id: str, keep_results: bool = True):
        """Cleanup job-specific data"""
        try:
            # Clean temp directory
            temp_path = self.temp_dir / job_id
            if temp_path.exists():
                import shutil
                shutil.rmtree(temp_path)
                logger.info(f"Cleaned temporary data for job {job_id}")
            
            # Optionally clean results
            if not keep_results:
                results_path = self.results_dir / job_id
                if results_path.exists():
                    shutil.rmtree(results_path)
                    logger.info(f"Cleaned results for job {job_id}")
                    
        except Exception as e:
            logger.error(f"Error cleaning up job {job_id}: {e}")
    
    def stop_job_container(self, job_id: str) -> bool:
        """Stop and remove a specific job's container"""
        try:
            if job_id in self.active_containers:
                container = self.active_containers[job_id]
                container.stop(timeout=10)
                container.remove(force=True)
                del self.active_containers[job_id]
                logger.info(f"Successfully stopped container for job {job_id}")
                return True
            else:
                logger.warning(f"No active container found for job {job_id}")
                return False
        except Exception as e:
            logger.error(f"Error stopping container for job {job_id}: {e}")
            return False
    
    def get_container_stats(self) -> Dict:
        """Get Docker container resource statistics"""
        try:
            # Handle subprocess mode
            if self.docker_client == "subprocess":
                import subprocess
                import os
                import psutil
                
                # Get running containers via subprocess
                result = subprocess.run(['docker', 'ps', '--format', 'table {{.Names}}\t{{.Image}}'], 
                                      capture_output=True, text=True, check=True)
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')[1:]  # Skip header
                    eemt_containers = [line.split('\t')[0] for line in lines if self.container_config.image in line]
                    
                    # Get actual system resources
                    cpu_count = os.cpu_count() or psutil.cpu_count() or 4
                    try:
                        memory_info = psutil.virtual_memory()
                        memory_gb = round(memory_info.total / (1024**3), 1)
                    except:
                        memory_gb = "N/A"
                    
                    # Get total container count via Docker
                    try:
                        docker_info_result = subprocess.run(['docker', 'info', '--format', '{{json .}}'], 
                                                          capture_output=True, text=True, check=True)
                        if docker_info_result.returncode == 0:
                            import json
                            docker_info = json.loads(docker_info_result.stdout)
                            containers_running = docker_info.get("ContainersRunning", len(eemt_containers))
                        else:
                            containers_running = len(eemt_containers)
                    except:
                        containers_running = len(eemt_containers)
                    
                    return {
                        "total_containers": len(eemt_containers),
                        "running_jobs": eemt_containers,
                        "system_stats": {
                            "cpus": cpu_count,
                            "memory": f"{memory_gb} GB",
                            "containers_running": containers_running
                        }
                    }
                else:
                    return {"error": "Failed to get container stats via subprocess"}
            
            # Handle normal Docker client mode
            # Get running containers
            containers = self.docker_client.containers.list()
            eemt_containers = [c for c in containers if self.container_config.image in c.image.tags]
            
            stats = {
                "total_containers": len(eemt_containers),
                "running_jobs": [c.name for c in eemt_containers],
                "system_stats": {}
            }
            
            # Get system info
            info = self.docker_client.info()
            stats["system_stats"] = {
                "cpus": info.get("NCPU", 0),
                "memory": info.get("MemTotal", 0),
                "containers_running": info.get("ContainersRunning", 0)
            }
            
            return stats
            
        except Exception as e:
            logger.error(f"Error getting container stats: {e}")
            return {"error": str(e)}
    
    async def _execute_mock_workflow(
        self, 
        job_id: str, 
        workflow_type: str, 
        dem_filename: str, 
        parameters: Dict
    ) -> AsyncGenerator[str, None]:
        """Mock workflow execution for testing without Docker"""
        
        yield "STATUS: Mock workflow starting - Docker not available"
        yield f"STATUS: Processing {workflow_type} workflow for {dem_filename}"
        
        # Simulate workflow steps
        steps = [
            "Initializing GRASS environment",
            "Loading DEM data",
            "Setting up coordinate system",
            "Calculating solar positions",
            "Processing daily calculations",
            "Generating intermediate results",
            "Aggregating monthly data",
            "Finalizing outputs",
            "Cleaning up temporary files"
        ]
        
        if workflow_type == "eemt":
            steps.extend([
                "Downloading climate data",
                "Processing DAYMET integration", 
                "Calculating EEMT values",
                "Generating final EEMT maps"
            ])
        
        total_steps = len(steps)
        
        for i, step in enumerate(steps):
            progress = (i + 1) / total_steps * 100
            yield f"PROGRESS: {progress:.1f}% ({i+1}/{total_steps} tasks)"
            yield f"STATUS: {step}"
            
            # Simulate processing time
            await asyncio.sleep(2)
        
        # Create mock output files
        job_results_dir = self.results_dir / job_id
        job_results_dir.mkdir(exist_ok=True, parents=True)
        
        # Create mock result files
        mock_files = [
            "global/daily/total_sun_day_001.tif",
            "global/monthly/total_sun_jan_sum.tif",
            "insol/daily/hours_sun_day_001.tif"
        ]
        
        if workflow_type == "eemt":
            mock_files.extend([
                "eemt/EEMT_Topo_jan_2020.tif",
                "eemt/EEMT_Trad_jan_2020.tif"
            ])
        
        for mock_file in mock_files:
            mock_path = job_results_dir / mock_file
            mock_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Create small mock GeoTIFF (just empty file for demo)
            with open(mock_path, 'w') as f:
                f.write(f"Mock {workflow_type} result file\n")
                f.write(f"Job ID: {job_id}\n")
                f.write(f"DEM: {dem_filename}\n")
                f.write(f"Parameters: {json.dumps(parameters, indent=2)}\n")
        
        yield "COMPLETED: Mock workflow execution finished successfully"
    
    async def _execute_subprocess_workflow(
        self, 
        job_id: str, 
        workflow_type: str, 
        dem_filename: str, 
        parameters: Dict
    ) -> AsyncGenerator[str, None]:
        """Execute workflow using subprocess Docker calls with improved progress tracking"""
        
        try:
            # Prepare paths
            uploads_path = str(self.uploads_dir)
            results_path = str(self.results_dir / job_id)
            temp_path = str(self.temp_dir / job_id)
            cache_path = str(self.cache_dir)
            
            # Check if DEM file exists
            dem_file_path = self.uploads_dir / dem_filename
            if not dem_file_path.exists():
                # Check for uploaded files with job_id prefix
                possible_files = list(self.uploads_dir.glob(f"*_{dem_filename}"))
                if possible_files:
                    dem_file_path = possible_files[0]
                    dem_filename = dem_file_path.name
                    logger.info(f"Found uploaded DEM file: {dem_filename}")
                else:
                    yield f"ERROR: DEM file not found: {dem_filename}"
                    return
            
            # Ensure directories exist
            Path(results_path).mkdir(parents=True, exist_ok=True)
            Path(temp_path).mkdir(parents=True, exist_ok=True)
            
            # Build container command
            container_cmd = self._build_container_command(
                workflow_type, dem_filename, parameters, job_id
            )
            
            # Build docker run command with better logging
            docker_run_cmd = [
                'docker', 'run',
                '--name', f'eemt-job-{job_id[:8]}',  # Container name for tracking
                '--rm',  # Remove after completion
                '-v', f'{uploads_path}:/data/input:ro',
                '-v', f'{results_path}:/data/output:rw',
                '-v', f'{temp_path}:/data/temp:rw',
                '-v', f'{cache_path}:/data/cache:rw',
                # CPU and memory limits
                '--cpus', str(parameters.get('num_threads', 4)),
                '--memory', self.container_config.memory_limit,
                # Environment variables
                '-e', 'PYTHONUNBUFFERED=1',  # Important for real-time output
                '-e', 'EEMT_NUM_THREADS=' + str(parameters.get('num_threads', 4)),
                '-e', 'EEMT_STEP=' + str(parameters.get('step', 15)),
                '-e', 'EEMT_LINKE_VALUE=' + str(parameters.get('linke_value', 3.0)),
                '-e', 'EEMT_ALBEDO_VALUE=' + str(parameters.get('albedo_value', 0.2)),
                '-e', 'GRASS_MESSAGE_FORMAT=plain',
                '-e', 'GRASS_VERBOSE=1',
                self.container_config.image
            ] + container_cmd
            
            yield "STATUS: Container environment ready"
            yield "PROGRESS: 30%"
            
            logger.info(f"Starting Docker container for job {job_id}")
            logger.debug(f"Docker command: {' '.join(docker_run_cmd)}")
            
            # Execute container via subprocess
            import asyncio
            
            process = await asyncio.create_subprocess_exec(
                *docker_run_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT
            )
            
            # Store process for potential cancellation
            self.active_containers[job_id] = process
            
            yield "STATUS: Workflow initialization started"
            yield "PROGRESS: 35%"
            
            # Track workflow progress
            progress_started = False
            tasks_completed = 0
            total_tasks = 365 if workflow_type == "sol" else 816  # Estimate task count
            
            # Monitor process output with better progress tracking
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                    
                output = line.decode('utf-8', errors='ignore').strip()
                if output:
                    logger.debug(f"Container output: {output}")
                    
                    # Parse different types of output
                    if "initializing grass" in output.lower():
                        yield "STATUS: Initializing GRASS GIS environment"
                        yield "PROGRESS: 40%"
                        progress_started = True
                    elif "loading dem" in output.lower():
                        yield "STATUS: Loading and processing DEM data"
                        yield "PROGRESS: 45%"
                    elif "starting solar calculations" in output.lower() or "running r.sun" in output.lower():
                        yield "STATUS: Starting solar radiation calculations"
                        yield "PROGRESS: 50%"
                    elif "task" in output.lower() and "/" in output:
                        # Parse task progress
                        import re
                        match = re.search(r'(\d+)\s*/\s*(\d+)', output)
                        if match:
                            current = int(match.group(1))
                            total = int(match.group(2))
                            # Calculate progress (50-95% for main tasks)
                            progress = 50 + (current / total * 45)
                            yield f"PROGRESS: {progress:.1f}%"
                            yield f"STATUS: Processing task {current}/{total}"
                    elif "monthly aggregation" in output.lower():
                        yield "STATUS: Generating monthly aggregations"
                        yield "PROGRESS: 95%"
                    elif "workflow completed" in output.lower() or "successfully" in output.lower():
                        yield "STATUS: Finalizing results"
                        yield "PROGRESS: 98%"
                    elif "error" in output.lower() or "failed" in output.lower():
                        yield f"ERROR: {output}"
                    elif progress_started:
                        # Generic progress tracking
                        tasks_completed += 1
                        if tasks_completed % 10 == 0:  # Update every 10 tasks
                            progress = min(50 + (tasks_completed / total_tasks * 45), 95)
                            yield f"PROGRESS: {progress:.1f}%"
            
            # Wait for completion
            return_code = await process.wait()
            
            if return_code == 0:
                yield "PROGRESS: 100%"
                yield "COMPLETED: Workflow execution finished successfully"
            else:
                yield f"ERROR: Workflow failed with exit code {return_code}"
                
            # Clean up
            if job_id in self.active_containers:
                del self.active_containers[job_id]
                
        except asyncio.CancelledError:
            # Handle cancellation
            if job_id in self.active_containers:
                process = self.active_containers[job_id]
                process.terminate()
                await process.wait()
                del self.active_containers[job_id]
            yield "ERROR: Workflow cancelled by user"
            raise
            
        except Exception as e:
            logger.error(f"Subprocess workflow execution failed: {e}")
            yield f"ERROR: Workflow execution failed: {str(e)}"
            
            # Clean up on error
            if job_id in self.active_containers:
                del self.active_containers[job_id]