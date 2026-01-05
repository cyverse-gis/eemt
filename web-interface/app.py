#!/usr/bin/env python3
"""
EEMT Web Interface - Local Mode
FastAPI-based web service for local EEMT and solar radiation workflow execution
"""

import os
import asyncio
import sqlite3
import uuid
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict
import tempfile
import shutil
import subprocess
import logging

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import uvicorn

# Import container workflow manager
from containers.workflow_manager import WorkflowManager, ContainerConfig, NodeType

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="EEMT Local Workflow Service", version="1.0.0")

# Configuration
BASE_DIR = Path(__file__).parent
TEMPLATES_DIR = BASE_DIR / "templates"
STATIC_DIR = BASE_DIR / "static"
UPLOADS_DIR = BASE_DIR / "uploads"
RESULTS_DIR = BASE_DIR / "results"
# Use a writable location for the database
DB_PATH = Path("/tmp") / "jobs.db" if os.path.exists("/tmp") else BASE_DIR / "jobs.db"

# Create directories if they don't exist
for dir_path in [UPLOADS_DIR, RESULTS_DIR, STATIC_DIR, TEMPLATES_DIR]:
    dir_path.mkdir(exist_ok=True)

# Mount static files with cache busting for development
class NoCacheStaticFiles(StaticFiles):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
    
    async def __call__(self, scope, receive, send):
        response = await super().__call__(scope, receive, send)
        # Add no-cache headers for development
        if hasattr(response, 'headers'):
            response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
            response.headers["Pragma"] = "no-cache"
            response.headers["Expires"] = "0"
        return response

app.mount("/static", NoCacheStaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)

# Initialize container workflow manager
workflow_manager = WorkflowManager(BASE_DIR, NodeType.LOCAL)

# Database initialization
def init_database():
    """Initialize SQLite database for job tracking"""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY,
            workflow_type TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            started_at TIMESTAMP,
            completed_at TIMESTAMP,
            parameters TEXT,
            dem_filename TEXT,
            error_message TEXT,
            progress INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    conn.close()

init_database()

class JobStatus:
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"

class JobManager:
    """Simple job management for local execution"""
    
    def __init__(self):
        self.active_jobs: Dict[str, subprocess.Popen] = {}
        self.active_containers: Dict[str, str] = {}  # job_id -> container_id mapping
    
    def create_job(self, workflow_type: str, dem_filename: str, parameters: dict) -> str:
        """Create a new job entry in database"""
        job_id = str(uuid.uuid4())
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT INTO jobs (id, workflow_type, status, dem_filename, parameters) VALUES (?, ?, ?, ?, ?)",
            (job_id, workflow_type, JobStatus.PENDING, dem_filename, json.dumps(parameters))
        )
        conn.commit()
        conn.close()
        return job_id
    
    def update_status(self, job_id: str, status: str, progress: int = None, error: str = None):
        """Update job status in database"""
        conn = sqlite3.connect(DB_PATH)
        
        # Set timestamps based on status
        current_time = datetime.now().isoformat()
        
        if status == JobStatus.RUNNING:
            # Set started_at when job starts running
            if progress is not None:
                conn.execute(
                    "UPDATE jobs SET status = ?, progress = ?, error_message = ?, started_at = COALESCE(started_at, ?) WHERE id = ?",
                    (status, progress, error, current_time, job_id)
                )
            else:
                conn.execute(
                    "UPDATE jobs SET status = ?, error_message = ?, started_at = COALESCE(started_at, ?) WHERE id = ?",
                    (status, error, current_time, job_id)
                )
        elif status in [JobStatus.COMPLETED, JobStatus.FAILED]:
            # Set completed_at when job finishes (success or failure)
            if progress is not None:
                conn.execute(
                    "UPDATE jobs SET status = ?, progress = ?, error_message = ?, completed_at = ? WHERE id = ?",
                    (status, progress, error, current_time, job_id)
                )
            else:
                conn.execute(
                    "UPDATE jobs SET status = ?, error_message = ?, completed_at = ? WHERE id = ?",
                    (status, error, current_time, job_id)
                )
        else:
            # For other statuses (PENDING), just update status/progress
            if progress is not None:
                conn.execute(
                    "UPDATE jobs SET status = ?, progress = ?, error_message = ? WHERE id = ?",
                    (status, progress, error, job_id)
                )
            else:
                conn.execute(
                    "UPDATE jobs SET status = ?, error_message = ? WHERE id = ?",
                    (status, error, job_id)
                )
        
        conn.commit()
        conn.close()
    
    def get_job(self, job_id: str) -> Optional[dict]:
        """Get job details from database"""
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
        row = cursor.fetchone()
        conn.close()
        
        if row:
            return {
                "id": row[0],
                "workflow_type": row[1],
                "status": row[2],
                "created_at": row[3],
                "started_at": row[4],
                "completed_at": row[5],
                "parameters": json.loads(row[6]),
                "dem_filename": row[7],
                "error_message": row[8],
                "progress": row[9]
            }
        return None
    
    def list_jobs(self) -> List[dict]:
        """List all jobs from database"""
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.execute("SELECT * FROM jobs ORDER BY created_at DESC")
        rows = cursor.fetchall()
        conn.close()
        
        jobs = []
        for row in rows:
            jobs.append({
                "id": row[0],
                "workflow_type": row[1],
                "status": row[2],
                "created_at": row[3],
                "dem_filename": row[7],
                "progress": row[9]
            })
        return jobs
    
    def delete_job(self, job_id: str) -> tuple[bool, str]:
        """Delete job from database and clean up associated files
        Returns: (success, error_message)
        """
        try:
            # First check if job exists
            job = self.get_job(job_id)
            if not job:
                return False, "Job not found"
            
            # Don't allow deletion of running jobs
            if job["status"] == JobStatus.RUNNING:
                return False, "Cannot delete running job"
            
            # Delete from database
            conn = sqlite3.connect(DB_PATH)
            conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
            conn.commit()
            conn.close()
            
            # Clean up files
            # Remove results directory if it exists
            results_path = RESULTS_DIR / job_id
            if results_path.exists():
                shutil.rmtree(results_path)
                logger.info(f"Deleted results for job {job_id}")
            
            # Remove any zip files
            zip_path = RESULTS_DIR / f"{job_id}_results.zip"
            if zip_path.exists():
                zip_path.unlink()
            
            # Remove uploaded DEM file if it exists
            for upload_file in UPLOADS_DIR.glob(f"{job_id}_*"):
                upload_file.unlink()
                logger.info(f"Deleted upload file: {upload_file}")
            
            logger.info(f"Successfully deleted job {job_id}")
            return True, ""
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error deleting job {job_id}: {error_msg}")
            return False, f"Database or filesystem error: {error_msg}"
    
    def cancel_job(self, job_id: str) -> bool:
        """Cancel a running job"""
        try:
            job = self.get_job(job_id)
            if not job:
                return False
            
            # Only cancel running jobs
            if job["status"] != JobStatus.RUNNING:
                return False
            
            # Try to stop container if it exists
            if job_id in self.active_containers:
                container_id = self.active_containers[job_id]
                try:
                    # This will be handled by workflow_manager
                    logger.info(f"Requesting cancellation of container {container_id} for job {job_id}")
                    # The container will be stopped in execute_containerized_workflow
                except Exception as e:
                    logger.warning(f"Failed to stop container: {e}")
                
                # Remove from active containers
                del self.active_containers[job_id]
            
            # Update job status
            self.update_status(job_id, JobStatus.FAILED, error="Job cancelled by user")
            logger.info(f"Successfully cancelled job {job_id}")
            return True
            
        except Exception as e:
            logger.error(f"Error cancelling job {job_id}: {e}")
            return False
    
    def cleanup_old_jobs(self, success_retention_days: int = 7, failed_retention_hours: int = 12, dry_run: bool = False) -> dict:
        """Clean up old job data based on retention policies"""
        from datetime import timedelta
        
        cleanup_stats = {
            'processed_jobs': 0,
            'successful_cleaned': 0,
            'failed_deleted': 0,
            'space_freed_mb': 0.0,
            'errors': []
        }
        
        try:
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            
            # Calculate cutoff times
            now = datetime.now()
            success_cutoff = now - timedelta(days=success_retention_days)
            failed_cutoff = now - timedelta(hours=failed_retention_hours)
            
            # Get successful jobs eligible for data cleanup (preserve config)
            cursor.execute("""
                SELECT id, dem_filename FROM jobs 
                WHERE status = 'completed' 
                AND completed_at IS NOT NULL 
                AND datetime(completed_at) < ?
            """, (success_cutoff.isoformat(),))
            
            successful_jobs = cursor.fetchall()
            
            for job_id, dem_filename in successful_jobs:
                if not dry_run:
                    # Clean up results directory but keep job config
                    results_path = RESULTS_DIR / job_id
                    if results_path.exists():
                        cleanup_stats['space_freed_mb'] += self._get_directory_size_mb(results_path)
                        shutil.rmtree(results_path)
                
                cleanup_stats['successful_cleaned'] += 1
                cleanup_stats['processed_jobs'] += 1
            
            # Get failed jobs eligible for complete deletion
            cursor.execute("""
                SELECT id, dem_filename FROM jobs 
                WHERE status = 'failed' 
                AND completed_at IS NOT NULL 
                AND datetime(completed_at) < ?
            """, (failed_cutoff.isoformat(),))
            
            failed_jobs = cursor.fetchall()
            
            for job_id, dem_filename in failed_jobs:
                if not dry_run:
                    # Complete cleanup including database entry
                    results_path = RESULTS_DIR / job_id
                    if results_path.exists():
                        cleanup_stats['space_freed_mb'] += self._get_directory_size_mb(results_path)
                        shutil.rmtree(results_path)
                    
                    # Remove uploaded DEM files
                    if dem_filename:
                        dem_path = UPLOADS_DIR / dem_filename
                        if dem_path.exists():
                            cleanup_stats['space_freed_mb'] += dem_path.stat().st_size / (1024 * 1024)
                            dem_path.unlink()
                    
                    # Remove job from database
                    conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
                
                cleanup_stats['failed_deleted'] += 1
                cleanup_stats['processed_jobs'] += 1
            
            if not dry_run:
                conn.commit()
            conn.close()
            
        except Exception as e:
            error_msg = f"Error during cleanup: {str(e)}"
            logger.error(error_msg)
            cleanup_stats['errors'].append(error_msg)
        
        return cleanup_stats
    
    def _get_directory_size_mb(self, path: Path) -> float:
        """Calculate directory size in MB"""
        try:
            total_size = 0
            for file_path in path.rglob('*'):
                if file_path.is_file():
                    total_size += file_path.stat().st_size
            return total_size / (1024 * 1024)
        except Exception:
            return 0.0

job_manager = JobManager()

# Routes
@app.get("/", response_class=HTMLResponse)
@app.head("/")
async def home(request: Request):
    """Main page with job submission form"""
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/app.js")
@app.head("/app.js")
async def get_app_js(request: Request):
    """Serve app.js with no-cache headers"""
    js_file = STATIC_DIR / "app.js"
    response = FileResponse(js_file, media_type="application/javascript")
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    # For HEAD requests, FastAPI will automatically handle the response body
    return response

@app.get("/style.css")
@app.head("/style.css")
async def get_style_css(request: Request):
    """Serve style.css with no-cache headers"""
    css_file = STATIC_DIR / "style.css"
    response = FileResponse(css_file, media_type="text/css")
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

@app.post("/api/upload-file")
async def upload_file(file: UploadFile = File(...)):
    """Upload a DEM file immediately when selected"""
    
    # Validate file type
    if not file.filename.lower().endswith(('.tif', '.tiff')):
        raise HTTPException(status_code=400, detail="Only .tif and .tiff files are supported")
    
    # Generate unique filename
    unique_filename = f"{uuid.uuid4()}_{file.filename}"
    file_path = UPLOADS_DIR / unique_filename
    
    try:
        # Save uploaded file
        with open(file_path, "wb") as buffer:
            content = await file.read()
            buffer.write(content)
        
        logger.info(f"File uploaded successfully: {unique_filename} ({len(content)} bytes)")
        
        return {
            "status": "success",
            "filename": unique_filename,
            "original_name": file.filename,
            "size": len(content),
            "message": f"File {file.filename} uploaded successfully"
        }
        
    except Exception as e:
        logger.error(f"File upload failed: {e}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

@app.post("/api/submit-job")
async def submit_job(
    workflow_type: str = Form(...),
    dem_file: UploadFile = File(...),
    step: float = Form(15.0),
    linke_value: float = Form(3.0),
    albedo_value: float = Form(0.2),
    num_threads: int = Form(4),
    start_year: Optional[int] = Form(None),
    end_year: Optional[int] = Form(None)
):
    """Submit a new EEMT or solar workflow job"""
    
    # Validate file
    if not dem_file.filename.endswith(('.tif', '.tiff')):
        raise HTTPException(status_code=400, detail="DEM file must be a GeoTIFF (.tif or .tiff)")
    
    # Generate job ID first
    job_id = str(uuid.uuid4())
    
    # Save uploaded file with job ID prefix
    dem_filename = f"{job_id}_{dem_file.filename}"
    dem_path = UPLOADS_DIR / dem_filename
    
    try:
        with open(dem_path, "wb") as buffer:
            shutil.copyfileobj(dem_file.file, buffer)
        logger.info(f"Saved DEM file: {dem_filename}")
    except Exception as e:
        logger.error(f"Failed to save uploaded file: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to save uploaded file: {str(e)}")
    
    # Create job parameters
    parameters = {
        "step": step,
        "linke_value": linke_value,
        "albedo_value": albedo_value,
        "num_threads": num_threads,
    }
    
    if workflow_type == "eemt":
        parameters["start_year"] = start_year or 2020
        parameters["end_year"] = end_year or 2020
    
    # Create job in database (use the generated job_id)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "INSERT INTO jobs (id, workflow_type, status, dem_filename, parameters, progress) VALUES (?, ?, ?, ?, ?, ?)",
            (job_id, workflow_type, JobStatus.PENDING, dem_filename, json.dumps(parameters), 0)
        )
        conn.commit()
        logger.info(f"Created job {job_id} in database")
    except Exception as e:
        logger.error(f"Failed to create job in database: {e}")
        raise HTTPException(status_code=500, detail="Failed to create job record")
    finally:
        conn.close()
    
    # Start containerized job execution asynchronously
    asyncio.create_task(execute_containerized_workflow(job_id, workflow_type, dem_filename, parameters))
    
    return {"job_id": job_id, "status": "submitted"}

async def execute_containerized_workflow(job_id: str, workflow_type: str, dem_filename: str, parameters: dict):
    """Execute workflow in Docker container with improved progress tracking"""
    try:
        logger.info(f"Starting containerized workflow for job {job_id}")
        logger.info(f"Workflow type: {workflow_type}, DEM: {dem_filename}")
        logger.info(f"Parameters: {parameters}")
        
        # Update job status to running
        job_manager.update_status(job_id, JobStatus.RUNNING, progress=5)
        
        # Check Docker availability first
        if not workflow_manager.check_docker_availability():
            logger.error(f"Docker not available for job {job_id}")
            job_manager.update_status(job_id, JobStatus.FAILED, error="Docker not available or image not found")
            return
        
        # Execute workflow in container and monitor progress
        progress_stream = workflow_manager.execute_workflow(
            job_id, workflow_type, dem_filename, parameters
        )
        
        last_progress = 0
        async for progress_update in progress_stream:
            logger.info(f"Job {job_id}: {progress_update}")
            
            if progress_update.startswith("PROGRESS:"):
                # Extract progress percentage
                try:
                    progress_text = progress_update.replace("PROGRESS:", "").strip()
                    if "%" in progress_text:
                        progress_pct = float(progress_text.split("%")[0])
                        # Only update if progress has changed significantly
                        if progress_pct != last_progress:
                            job_manager.update_status(job_id, JobStatus.RUNNING, progress=int(progress_pct))
                            last_progress = progress_pct
                except Exception as e:
                    logger.warning(f"Failed to parse progress: {e}")
                    
            elif progress_update.startswith("STATUS:"):
                # Status update without specific progress
                status_text = progress_update.replace("STATUS:", "").strip()
                logger.info(f"Job {job_id} status: {status_text}")
                
            elif progress_update.startswith("COMPLETED:"):
                # Workflow completed successfully
                job_manager.update_status(job_id, JobStatus.COMPLETED, progress=100)
                logger.info(f"Job {job_id} completed successfully")
                break
                
            elif progress_update.startswith("ERROR:") or progress_update.startswith("FAILED:"):
                # Workflow failed
                error_msg = progress_update.replace("ERROR:", "").replace("FAILED:", "").strip()
                job_manager.update_status(job_id, JobStatus.FAILED, error=error_msg)
                logger.error(f"Job {job_id} failed: {error_msg}")
                break
        
        # Final status check
        job = job_manager.get_job(job_id)
        if job and job["status"] == JobStatus.RUNNING:
            # If still running, mark as completed (fallback)
            job_manager.update_status(job_id, JobStatus.COMPLETED, progress=100)
            
    except Exception as e:
        error_msg = f"Container execution failed: {str(e)}"
        logger.error(f"Job {job_id} error: {error_msg}")
        job_manager.update_status(job_id, JobStatus.FAILED, error=error_msg)
    finally:
        # Cleanup temporary data but keep results
        try:
            workflow_manager.cleanup_job_data(job_id, keep_results=True)
        except Exception as cleanup_error:
            logger.warning(f"Cleanup warning for job {job_id}: {cleanup_error}")

@app.get("/api/jobs")
async def list_jobs(status: Optional[str] = None, limit: Optional[int] = None):
    """List all jobs with optional filtering"""
    jobs = job_manager.list_jobs()
    
    # Filter by status if requested
    if status:
        jobs = [j for j in jobs if j["status"] == status]
    
    # Limit results if requested
    if limit:
        jobs = jobs[:limit]
    
    return jobs

@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str):
    """Get specific job details"""
    job = job_manager.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job

@app.get("/api/jobs/{job_id}/logs")
async def get_job_logs(job_id: str, tail: int = 50):
    """Get job logs (last N lines)"""
    job = job_manager.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    # Look for log files in the results directory
    results_path = RESULTS_DIR / job_id
    log_content = ""
    
    # Check for various log files
    log_files = [
        results_path / "workflow.log",
        results_path / "task_output.log",
        results_path / "sys.err",
        results_path / "container.log"
    ]
    
    for log_file in log_files:
        if log_file.exists():
            try:
                with open(log_file, 'r') as f:
                    lines = f.readlines()
                    # Get last N lines
                    if tail > 0:
                        lines = lines[-tail:]
                    log_content += f"\n--- {log_file.name} ---\n"
                    log_content += ''.join(lines)
            except Exception as e:
                logger.warning(f"Could not read log file {log_file}: {e}")
    
    if not log_content:
        # Try to get container logs if available
        if job_id in job_manager.active_containers:
            try:
                container_id = job_manager.active_containers[job_id]
                # Get logs from Docker
                import subprocess
                result = subprocess.run(
                    ["docker", "logs", "--tail", str(tail), container_id],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    log_content = result.stdout
                else:
                    log_content = "Container logs not available"
            except Exception as e:
                logger.warning(f"Could not get container logs: {e}")
                log_content = "Logs not yet available. Workflow may still be initializing..."
        else:
            log_content = "No logs available yet. Please wait for workflow to start..."
    
    return log_content

@app.get("/api/jobs/{job_id}/results")
async def download_results(job_id: str):
    """Download job results as ZIP file"""
    job = job_manager.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    if job["status"] != JobStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Job not completed")
    
    results_path = RESULTS_DIR / job_id
    if not results_path.exists():
        raise HTTPException(status_code=404, detail="Results not found")
    
    # Create ZIP archive
    zip_path = RESULTS_DIR / f"{job_id}_results.zip"
    shutil.make_archive(str(zip_path)[:-4], 'zip', results_path)
    
    return FileResponse(
        zip_path,
        media_type="application/zip",
        filename=f"eemt_results_{job_id}.zip"
    )

@app.get("/health")
async def health_check():
    """Simple health check endpoint for container health monitoring"""
    try:
        # Basic checks
        db_accessible = DB_PATH.exists()
        directories_exist = all(dir_path.exists() for dir_path in [UPLOADS_DIR, RESULTS_DIR])
        
        if db_accessible and directories_exist:
            return {"status": "healthy", "timestamp": datetime.now().isoformat()}
        else:
            raise HTTPException(status_code=503, detail="Service unavailable")
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Service unhealthy")

@app.get("/api/system/status")
async def system_status():
    """Get enhanced system and Docker status"""
    try:
        docker_available = workflow_manager.check_docker_availability()
        container_stats = workflow_manager.get_container_stats() if docker_available else {}
        
        # Count active jobs
        active_jobs = len([j for j in job_manager.list_jobs() if j["status"] == JobStatus.RUNNING])
        
        # Check if Docker image exists
        image_exists = False
        if docker_available:
            try:
                import subprocess
                result = subprocess.run(
                    ["docker", "images", "-q", workflow_manager.container_config.image],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                image_exists = bool(result.stdout.strip())
            except:
                pass
        
        return {
            "docker_available": docker_available,
            "container_stats": container_stats,
            "image_name": workflow_manager.container_config.image,
            "image_exists": image_exists,
            "active_jobs": active_jobs,
            "active_containers": list(job_manager.active_containers.keys()),
            "system_info": {
                "uploads_dir": str(UPLOADS_DIR),
                "results_dir": str(RESULTS_DIR),
                "uploads_dir_exists": UPLOADS_DIR.exists(),
                "results_dir_exists": RESULTS_DIR.exists()
            }
        }
    except Exception as e:
        return {
            "docker_available": False,
            "error": str(e),
            "image_name": workflow_manager.container_config.image,
            "active_jobs": 0
        }

@app.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str):
    """Delete a job and its associated data"""
    success, error_msg = job_manager.delete_job(job_id)
    if success:
        # Also clean up through workflow manager
        try:
            workflow_manager.cleanup_job_data(job_id, keep_results=False)
        except Exception as e:
            logger.warning(f"Additional cleanup warning: {e}")
        return {"status": "success", "message": "Job deleted successfully"}
    else:
        if error_msg == "Job not found":
            raise HTTPException(status_code=404, detail=error_msg)
        elif error_msg == "Cannot delete running job":
            raise HTTPException(status_code=400, detail="Cannot delete running job. Please cancel it first.")
        else:
            # Return the actual error message instead of generic one
            raise HTTPException(status_code=500, detail=error_msg)

@app.post("/api/jobs/{job_id}/cancel")
async def cancel_job(job_id: str):
    """Cancel a running job"""
    # Check if job exists and is running
    job = job_manager.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    if job["status"] != JobStatus.RUNNING:
        raise HTTPException(status_code=400, detail=f"Job is not running (status: {job['status']})")
    
    # Try to stop the container if it's tracked
    try:
        # Use workflow manager's method to stop container
        if hasattr(workflow_manager, 'stop_job_container'):
            container_stopped = workflow_manager.stop_job_container(job_id)
            if container_stopped:
                logger.info(f"Successfully stopped container for job {job_id}")
            else:
                logger.warning(f"No container found or failed to stop container for job {job_id}")
    except Exception as e:
        logger.error(f"Error stopping container: {e}")
    
    # Update job status
    success = job_manager.cancel_job(job_id)
    if success:
        return {"status": "success", "message": "Job cancelled successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to cancel job")

@app.post("/api/cleanup")
async def cleanup_old_jobs(
    success_retention_days: int = 7,
    failed_retention_hours: int = 12, 
    dry_run: bool = False
):
    """Clean up old job data based on retention policies"""
    try:
        cleanup_stats = job_manager.cleanup_old_jobs(
            success_retention_days=success_retention_days,
            failed_retention_hours=failed_retention_hours,
            dry_run=dry_run
        )
        
        return {
            "status": "success", 
            "message": "Cleanup completed",
            "stats": cleanup_stats
        }
        
    except Exception as e:
        logger.error(f"Cleanup failed: {e}")
        raise HTTPException(status_code=500, detail=f"Cleanup failed: {str(e)}")

@app.get("/monitor", response_class=HTMLResponse)
async def monitor(request: Request):
    """Job monitoring page"""
    return templates.TemplateResponse("monitor.html", {"request": request})

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)