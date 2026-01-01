#!/usr/bin/env python3
"""
EEMT Job Data Cleanup Script

Automated cleanup of job output data while preserving job configurations:
- Successful jobs: Delete output data after 7 days, keep job config
- Failed jobs: Delete all data after 12 hours
- Configurable retention periods via environment variables or command line

Usage:
    python cleanup_jobs.py [--dry-run] [--success-retention-days 7] [--failed-retention-hours 12]
    
Environment Variables:
    EEMT_SUCCESS_RETENTION_DAYS=7    # Days to keep successful job data
    EEMT_FAILED_RETENTION_HOURS=12   # Hours to keep failed job data
    EEMT_DRY_RUN=true               # Preview cleanup actions without executing
"""

import os
import sys
import argparse
import sqlite3
import shutil
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Optional
import json

# Add the web-interface directory to Python path for imports
sys.path.append(str(Path(__file__).parent))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('cleanup_jobs.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class JobCleanupManager:
    """Manages automated cleanup of EEMT job data"""
    
    def __init__(self, base_dir: Path, dry_run: bool = False):
        self.base_dir = base_dir
        self.dry_run = dry_run
        self.db_path = base_dir / "jobs.db"
        self.results_dir = base_dir / "results"
        self.uploads_dir = base_dir / "uploads"
        
        # Retention policies (configurable)
        self.success_retention_days = int(os.getenv('EEMT_SUCCESS_RETENTION_DAYS', '7'))
        self.failed_retention_hours = int(os.getenv('EEMT_FAILED_RETENTION_HOURS', '12'))
        
        logger.info(f"Cleanup manager initialized:")
        logger.info(f"  Base directory: {self.base_dir}")
        logger.info(f"  Success retention: {self.success_retention_days} days")
        logger.info(f"  Failed retention: {self.failed_retention_hours} hours")
        logger.info(f"  Dry run mode: {self.dry_run}")
    
    def get_jobs_for_cleanup(self) -> Dict[str, List[Dict]]:
        """Get jobs eligible for cleanup based on retention policies"""
        if not self.db_path.exists():
            logger.warning(f"Database not found: {self.db_path}")
            return {"successful": [], "failed": []}
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Calculate cutoff times
        now = datetime.now()
        success_cutoff = now - timedelta(days=self.success_retention_days)
        failed_cutoff = now - timedelta(hours=self.failed_retention_hours)
        
        logger.info(f"Cleanup cutoff times:")
        logger.info(f"  Successful jobs completed before: {success_cutoff}")
        logger.info(f"  Failed jobs completed before: {failed_cutoff}")
        
        # Query successful jobs eligible for data cleanup (keep job config)
        cursor.execute("""
            SELECT id, workflow_type, status, completed_at, dem_filename, parameters
            FROM jobs 
            WHERE status = 'completed' 
            AND completed_at IS NOT NULL 
            AND datetime(completed_at) < ?
            ORDER BY completed_at ASC
        """, (success_cutoff.isoformat(),))
        
        successful_jobs = []
        for row in cursor.fetchall():
            successful_jobs.append({
                'id': row[0],
                'workflow_type': row[1],
                'status': row[2],
                'completed_at': row[3],
                'dem_filename': row[4],
                'parameters': json.loads(row[5]) if row[5] else {}
            })
        
        # Query failed jobs eligible for complete deletion
        cursor.execute("""
            SELECT id, workflow_type, status, completed_at, dem_filename, parameters
            FROM jobs 
            WHERE status = 'failed' 
            AND completed_at IS NOT NULL 
            AND datetime(completed_at) < ?
            ORDER BY completed_at ASC
        """, (failed_cutoff.isoformat(),))
        
        failed_jobs = []
        for row in cursor.fetchall():
            failed_jobs.append({
                'id': row[0],
                'workflow_type': row[1],
                'status': row[2],
                'completed_at': row[3],
                'dem_filename': row[4],
                'parameters': json.loads(row[5]) if row[5] else {}
            })
        
        conn.close()
        
        logger.info(f"Found {len(successful_jobs)} successful jobs for data cleanup")
        logger.info(f"Found {len(failed_jobs)} failed jobs for complete deletion")
        
        return {
            "successful": successful_jobs,
            "failed": failed_jobs
        }
    
    def cleanup_job_data(self, job: Dict, keep_job_config: bool = True) -> Dict[str, any]:
        """Clean up job data while optionally preserving job configuration"""
        job_id = job['id']
        cleanup_stats = {
            'job_id': job_id,
            'status': job['status'],
            'completed_at': job['completed_at'],
            'data_deleted': False,
            'config_preserved': keep_job_config,
            'files_deleted': [],
            'directories_deleted': [],
            'size_freed_mb': 0,
            'errors': []
        }
        
        logger.info(f"Processing job {job_id} ({job['status']}, completed: {job['completed_at']})")
        
        try:
            # Clean up results directory
            results_path = self.results_dir / job_id
            if results_path.exists():
                if not self.dry_run:
                    size_mb = self._get_directory_size_mb(results_path)
                    shutil.rmtree(results_path)
                    cleanup_stats['size_freed_mb'] += size_mb
                    logger.info(f"Deleted results directory: {results_path} ({size_mb:.1f} MB)")
                else:
                    size_mb = self._get_directory_size_mb(results_path)
                    cleanup_stats['size_freed_mb'] += size_mb
                    logger.info(f"[DRY RUN] Would delete results directory: {results_path} ({size_mb:.1f} MB)")
                
                cleanup_stats['directories_deleted'].append(str(results_path))
                cleanup_stats['data_deleted'] = True
            
            # Clean up uploaded DEM file
            if job.get('dem_filename'):
                dem_path = self.uploads_dir / job['dem_filename']
                if dem_path.exists():
                    if not self.dry_run:
                        size_mb = dem_path.stat().st_size / (1024 * 1024)
                        dem_path.unlink()
                        cleanup_stats['size_freed_mb'] += size_mb
                        logger.info(f"Deleted uploaded DEM: {dem_path} ({size_mb:.1f} MB)")
                    else:
                        size_mb = dem_path.stat().st_size / (1024 * 1024)
                        cleanup_stats['size_freed_mb'] += size_mb
                        logger.info(f"[DRY RUN] Would delete uploaded DEM: {dem_path} ({size_mb:.1f} MB)")
                    
                    cleanup_stats['files_deleted'].append(str(dem_path))
            
            # If not preserving config, remove job from database
            if not keep_job_config:
                if not self.dry_run:
                    conn = sqlite3.connect(self.db_path)
                    conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
                    conn.commit()
                    conn.close()
                    logger.info(f"Deleted job configuration from database: {job_id}")
                else:
                    logger.info(f"[DRY RUN] Would delete job configuration from database: {job_id}")
                
                cleanup_stats['config_preserved'] = False
        
        except Exception as e:
            error_msg = f"Error cleaning up job {job_id}: {str(e)}"
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
    
    def run_cleanup(self) -> Dict[str, any]:
        """Execute cleanup process and return summary statistics"""
        logger.info("Starting EEMT job data cleanup process")
        
        if self.dry_run:
            logger.info("=== DRY RUN MODE - NO CHANGES WILL BE MADE ===")
        
        # Get jobs eligible for cleanup
        jobs_to_clean = self.get_jobs_for_cleanup()
        
        cleanup_summary = {
            'start_time': datetime.now().isoformat(),
            'dry_run': self.dry_run,
            'successful_jobs_processed': 0,
            'failed_jobs_processed': 0,
            'total_size_freed_mb': 0,
            'configs_preserved': 0,
            'configs_deleted': 0,
            'errors': [],
            'job_details': []
        }
        
        # Process successful jobs (data cleanup, preserve config)
        for job in jobs_to_clean['successful']:
            try:
                stats = self.cleanup_job_data(job, keep_job_config=True)
                cleanup_summary['job_details'].append(stats)
                cleanup_summary['successful_jobs_processed'] += 1
                cleanup_summary['total_size_freed_mb'] += stats['size_freed_mb']
                if stats['config_preserved']:
                    cleanup_summary['configs_preserved'] += 1
                cleanup_summary['errors'].extend(stats['errors'])
            except Exception as e:
                error_msg = f"Failed to process successful job {job['id']}: {str(e)}"
                logger.error(error_msg)
                cleanup_summary['errors'].append(error_msg)
        
        # Process failed jobs (complete deletion)
        for job in jobs_to_clean['failed']:
            try:
                stats = self.cleanup_job_data(job, keep_job_config=False)
                cleanup_summary['job_details'].append(stats)
                cleanup_summary['failed_jobs_processed'] += 1
                cleanup_summary['total_size_freed_mb'] += stats['size_freed_mb']
                if not stats['config_preserved']:
                    cleanup_summary['configs_deleted'] += 1
                cleanup_summary['errors'].extend(stats['errors'])
            except Exception as e:
                error_msg = f"Failed to process failed job {job['id']}: {str(e)}"
                logger.error(error_msg)
                cleanup_summary['errors'].append(error_msg)
        
        cleanup_summary['end_time'] = datetime.now().isoformat()
        
        # Log summary
        logger.info("=== CLEANUP SUMMARY ===")
        logger.info(f"Successful jobs processed: {cleanup_summary['successful_jobs_processed']}")
        logger.info(f"Failed jobs processed: {cleanup_summary['failed_jobs_processed']}")
        logger.info(f"Total disk space freed: {cleanup_summary['total_size_freed_mb']:.1f} MB")
        logger.info(f"Job configs preserved: {cleanup_summary['configs_preserved']}")
        logger.info(f"Job configs deleted: {cleanup_summary['configs_deleted']}")
        logger.info(f"Errors encountered: {len(cleanup_summary['errors'])}")
        
        if cleanup_summary['errors']:
            logger.warning("Errors during cleanup:")
            for error in cleanup_summary['errors']:
                logger.warning(f"  - {error}")
        
        return cleanup_summary

def main():
    """Main entry point for cleanup script"""
    parser = argparse.ArgumentParser(
        description='EEMT Job Data Cleanup Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        '--dry-run', action='store_true',
        help='Preview cleanup actions without making changes'
    )
    parser.add_argument(
        '--success-retention-days', type=int, default=7,
        help='Days to retain successful job data (default: 7)'
    )
    parser.add_argument(
        '--failed-retention-hours', type=int, default=12,
        help='Hours to retain failed job data (default: 12)'
    )
    parser.add_argument(
        '--base-dir', type=Path, default=Path(__file__).parent,
        help='Base directory containing jobs.db and results/ (default: script directory)'
    )
    parser.add_argument(
        '--verbose', '-v', action='store_true',
        help='Enable verbose logging'
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Override environment variables with command line arguments
    if args.success_retention_days != 7:
        os.environ['EEMT_SUCCESS_RETENTION_DAYS'] = str(args.success_retention_days)
    if args.failed_retention_hours != 12:
        os.environ['EEMT_FAILED_RETENTION_HOURS'] = str(args.failed_retention_hours)
    if args.dry_run:
        os.environ['EEMT_DRY_RUN'] = 'true'
    
    # Initialize cleanup manager
    cleanup_manager = JobCleanupManager(args.base_dir, dry_run=args.dry_run)
    
    # Run cleanup
    try:
        summary = cleanup_manager.run_cleanup()
        
        # Save summary to file
        summary_file = args.base_dir / f"cleanup_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        logger.info(f"Cleanup summary saved to: {summary_file}")
        
        # Exit with appropriate code
        if summary['errors']:
            logger.warning(f"Cleanup completed with {len(summary['errors'])} errors")
            sys.exit(1)
        else:
            logger.info("Cleanup completed successfully")
            sys.exit(0)
            
    except Exception as e:
        logger.error(f"Cleanup process failed: {str(e)}")
        sys.exit(2)

if __name__ == '__main__':
    main()