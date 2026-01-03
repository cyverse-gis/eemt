#!/usr/bin/env python3
"""
Test script to verify the job monitoring fixes
"""

import sys
import time
import json
import requests
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

API_BASE = "http://127.0.0.1:5000"

def test_api_connectivity():
    """Test if the API is accessible"""
    try:
        response = requests.get(f"{API_BASE}/health", timeout=5)
        if response.status_code == 200:
            logger.info("✓ API is accessible")
            return True
        else:
            logger.error(f"✗ API health check failed: {response.status_code}")
            return False
    except requests.RequestException as e:
        logger.error(f"✗ Cannot connect to API: {e}")
        return False

def test_job_listing():
    """Test job listing endpoint"""
    try:
        response = requests.get(f"{API_BASE}/api/jobs", timeout=5)
        if response.status_code == 200:
            jobs = response.json()
            logger.info(f"✓ Job listing works - Found {len(jobs)} jobs")
            return jobs
        else:
            logger.error(f"✗ Job listing failed: {response.status_code}")
            return None
    except Exception as e:
        logger.error(f"✗ Job listing error: {e}")
        return None

def test_job_details(job_id):
    """Test job details endpoint"""
    try:
        response = requests.get(f"{API_BASE}/api/jobs/{job_id}", timeout=5)
        if response.status_code == 200:
            job = response.json()
            logger.info(f"✓ Job details accessible for {job_id}")
            logger.info(f"  Status: {job['status']}, Progress: {job.get('progress', 0)}%")
            return job
        elif response.status_code == 404:
            logger.warning(f"✗ Job {job_id} not found (404)")
            return None
        else:
            logger.error(f"✗ Job details failed: {response.status_code}")
            return None
    except Exception as e:
        logger.error(f"✗ Job details error: {e}")
        return None

def test_job_deletion(job_id):
    """Test job deletion endpoint"""
    try:
        # First check if job exists
        job = test_job_details(job_id)
        if not job:
            logger.info(f"Skipping deletion test - job {job_id} doesn't exist")
            return False
            
        # Check if job is running (cannot delete running jobs)
        if job['status'] == 'running':
            logger.info(f"Skipping deletion - job {job_id} is still running")
            return False
        
        # Attempt deletion
        response = requests.delete(f"{API_BASE}/api/jobs/{job_id}", timeout=5)
        
        if response.status_code == 200:
            logger.info(f"✓ Job {job_id} deleted successfully")
            result = response.json()
            logger.info(f"  Message: {result.get('message', 'No message')}")
            return True
        elif response.status_code == 404:
            logger.warning(f"✗ Job {job_id} not found (404)")
            return False
        elif response.status_code == 400:
            error_detail = response.json().get('detail', 'No detail')
            logger.warning(f"✗ Cannot delete job {job_id}: {error_detail}")
            return False
        elif response.status_code == 500:
            error_detail = response.json().get('detail', 'No detail')
            logger.error(f"✗ Server error deleting job {job_id}: {error_detail}")
            return False
        else:
            logger.error(f"✗ Unexpected status code: {response.status_code}")
            return False
            
    except Exception as e:
        logger.error(f"✗ Job deletion error: {e}")
        return False

def test_job_cancellation(job_id):
    """Test job cancellation endpoint"""
    try:
        # First check if job exists and is running
        job = test_job_details(job_id)
        if not job:
            logger.info(f"Skipping cancellation test - job {job_id} doesn't exist")
            return False
            
        if job['status'] != 'running':
            logger.info(f"Skipping cancellation - job {job_id} is not running (status: {job['status']})")
            return False
        
        # Attempt cancellation
        response = requests.post(f"{API_BASE}/api/jobs/{job_id}/cancel", timeout=5)
        
        if response.status_code == 200:
            logger.info(f"✓ Job {job_id} cancelled successfully")
            return True
        else:
            error_detail = response.json().get('detail', 'No detail')
            logger.error(f"✗ Failed to cancel job {job_id}: {error_detail}")
            return False
            
    except Exception as e:
        logger.error(f"✗ Job cancellation error: {e}")
        return False

def main():
    """Run all tests"""
    logger.info("="*60)
    logger.info("EEMT Job Monitor Test Suite")
    logger.info("="*60)
    
    # Test 1: API Connectivity
    logger.info("\n1. Testing API connectivity...")
    if not test_api_connectivity():
        logger.error("API is not accessible. Please ensure the web interface is running:")
        logger.error("  cd web-interface && python app.py")
        return 1
    
    # Test 2: Job Listing
    logger.info("\n2. Testing job listing...")
    jobs = test_job_listing()
    
    if jobs is None:
        logger.error("Could not retrieve job list")
        return 1
    
    # Test 3: Job Details (for each job)
    logger.info("\n3. Testing job details...")
    if jobs:
        for job in jobs[:3]:  # Test first 3 jobs
            test_job_details(job['id'])
    else:
        logger.info("No jobs to test details for")
    
    # Test 4: Job Deletion (only for completed/failed jobs)
    logger.info("\n4. Testing job deletion...")
    deleted_count = 0
    for job in jobs:
        if job['status'] in ['completed', 'failed']:
            if test_job_deletion(job['id']):
                deleted_count += 1
                if deleted_count >= 2:  # Only test deletion on 2 jobs
                    break
    
    if deleted_count == 0:
        logger.info("No deletable jobs found (all are pending/running)")
    
    # Test 5: Job Cancellation (only for running jobs)
    logger.info("\n5. Testing job cancellation...")
    cancelled = False
    for job in jobs:
        if job['status'] == 'running':
            if test_job_cancellation(job['id']):
                cancelled = True
                break
    
    if not cancelled:
        logger.info("No running jobs to cancel")
    
    # Final summary
    logger.info("\n" + "="*60)
    logger.info("Test suite completed!")
    logger.info("="*60)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())