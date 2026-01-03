#!/usr/bin/env python3
"""
Debug the delete job functionality
"""

import sqlite3
import json
from pathlib import Path

# Configuration
BASE_DIR = Path("/home/tswetnam/github/eemt/web-interface")
DB_PATH = BASE_DIR / "jobs.db"
UPLOADS_DIR = BASE_DIR / "uploads"
RESULTS_DIR = BASE_DIR / "results"

def check_job_in_db(job_id):
    """Check if job exists in database"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        print(f"Job found in database:")
        print(f"  ID: {row[0]}")
        print(f"  Type: {row[1]}")
        print(f"  Status: {row[2]}")
        print(f"  DEM: {row[7]}")
        return True
    else:
        print(f"Job {job_id} NOT found in database")
        return False

def check_job_files(job_id):
    """Check what files exist for the job"""
    print(f"\nChecking files for job {job_id}:")
    
    # Check results directory
    results_path = RESULTS_DIR / job_id
    if results_path.exists():
        print(f"  ✓ Results directory exists: {results_path}")
    else:
        print(f"  ✗ Results directory NOT found: {results_path}")
    
    # Check zip file
    zip_path = RESULTS_DIR / f"{job_id}_results.zip"
    if zip_path.exists():
        print(f"  ✓ Results ZIP exists: {zip_path}")
    else:
        print(f"  ✗ Results ZIP NOT found: {zip_path}")
    
    # Check uploaded files
    upload_files = list(UPLOADS_DIR.glob(f"{job_id}_*"))
    if upload_files:
        print(f"  ✓ Upload files found: {upload_files}")
    else:
        print(f"  ✗ No upload files found for pattern: {job_id}_*")

def attempt_delete(job_id):
    """Attempt to delete job manually"""
    print(f"\nAttempting manual deletion of job {job_id}...")
    
    try:
        # Delete from database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
        deleted_rows = cursor.rowcount
        conn.commit()
        conn.close()
        
        if deleted_rows > 0:
            print(f"  ✓ Deleted {deleted_rows} row(s) from database")
        else:
            print(f"  ✗ No rows deleted from database")
        
        # Clean up files
        import shutil
        
        # Remove results directory
        results_path = RESULTS_DIR / job_id
        if results_path.exists():
            shutil.rmtree(results_path)
            print(f"  ✓ Deleted results directory")
        
        # Remove zip file
        zip_path = RESULTS_DIR / f"{job_id}_results.zip"
        if zip_path.exists():
            zip_path.unlink()
            print(f"  ✓ Deleted results ZIP")
        
        # Remove upload files
        for upload_file in UPLOADS_DIR.glob(f"{job_id}_*"):
            upload_file.unlink()
            print(f"  ✓ Deleted upload file: {upload_file.name}")
        
        print("Manual deletion completed successfully!")
        return True
        
    except Exception as e:
        print(f"Error during manual deletion: {e}")
        return False

def main():
    job_id = "a8e48c4d-1a31-4e59-afa3-b2424dfff262"
    
    print("="*60)
    print("Job Deletion Debug Tool")
    print("="*60)
    
    # Check job in database
    if check_job_in_db(job_id):
        # Check associated files
        check_job_files(job_id)
        
        # Try manual deletion
        if attempt_delete(job_id):
            print("\n✓ Job deleted successfully!")
            
            # Verify deletion
            print("\nVerifying deletion...")
            if not check_job_in_db(job_id):
                print("✓ Job successfully removed from database")
            else:
                print("✗ Job still exists in database!")
    else:
        print("Job does not exist in database - nothing to delete")

if __name__ == "__main__":
    main()