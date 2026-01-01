// EEMT Monitor - Job monitoring JavaScript

document.addEventListener('DOMContentLoaded', function() {
    initializeMonitor();
    loadJobs();
    setupAutoRefresh();
});

let autoRefreshInterval = null;
let lastUpdateTime = null;

function initializeMonitor() {
    // Set up event handlers
    document.getElementById('auto_refresh').addEventListener('change', toggleAutoRefresh);
    
    // Initialize auto-refresh
    toggleAutoRefresh();
}

function toggleAutoRefresh() {
    const autoRefresh = document.getElementById('auto_refresh').checked;
    
    if (autoRefresh) {
        // Start auto-refresh every 5 seconds
        autoRefreshInterval = setInterval(refreshJobs, 5000);
        console.log('Auto-refresh enabled');
    } else {
        // Stop auto-refresh
        if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
            autoRefreshInterval = null;
        }
        console.log('Auto-refresh disabled');
    }
}

function setupAutoRefresh() {
    // Load jobs immediately
    refreshJobs();
}

async function refreshJobs() {
    await loadJobs();
    updateLastRefreshTime();
}

async function loadJobs() {
    try {
        const response = await fetch('/api/jobs');
        const jobs = await response.json();
        
        updateSummaryCards(jobs);
        updateJobsTable(jobs);
        
    } catch (error) {
        console.error('Error loading jobs:', error);
        showError('Failed to load jobs');
    }
}

function updateSummaryCards(jobs) {
    // Count jobs by status
    const counts = {
        pending: 0,
        running: 0,
        completed: 0,
        failed: 0
    };
    
    jobs.forEach(job => {
        counts[job.status] = (counts[job.status] || 0) + 1;
    });
    
    // Update cards
    document.getElementById('pending_count').textContent = counts.pending;
    document.getElementById('running_count').textContent = counts.running;
    document.getElementById('completed_count').textContent = counts.completed;
    document.getElementById('failed_count').textContent = counts.failed;
}

function updateJobsTable(jobs) {
    const tbody = document.getElementById('jobs_table_body');
    
    if (jobs.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="7" class="text-center text-muted">
                    <i class="bi bi-inbox fs-1"></i>
                    <br>No jobs found
                </td>
            </tr>
        `;
        return;
    }
    
    tbody.innerHTML = jobs.map(job => createJobRow(job)).join('');
}

function createJobRow(job) {
    const statusClass = getStatusClass(job.status);
    const statusIcon = getStatusIcon(job.status);
    const progressBar = job.status === 'running' ? 
        `<div class="progress" style="height: 4px;">
            <div class="progress-bar" style="width: ${job.progress || 0}%"></div>
         </div>` : '';
    
    const shortId = job.id.substring(0, 8);
    const createdDate = new Date(job.created_at).toLocaleString();
    
    return `
        <tr>
            <td>
                <code class="small">${shortId}</code>
                <button class="btn btn-sm btn-outline-secondary ms-1" 
                        onclick="copyToClipboard('${job.id}')" 
                        title="Copy full ID">
                    <i class="bi bi-copy"></i>
                </button>
            </td>
            <td>
                <span class="badge bg-primary">${job.workflow_type.toUpperCase()}</span>
            </td>
            <td>
                <span class="text-truncate d-inline-block" style="max-width: 150px;" title="${job.dem_filename}">
                    ${job.dem_filename}
                </span>
            </td>
            <td>
                <span class="badge ${statusClass}">
                    <i class="${statusIcon}"></i> ${job.status}
                </span>
                ${progressBar}
            </td>
            <td>
                ${job.status === 'running' ? 
                    `<div class="d-flex align-items-center">
                        <div class="progress me-2" style="width: 60px; height: 6px;">
                            <div class="progress-bar" style="width: ${job.progress || 0}%"></div>
                        </div>
                        <small>${job.progress || 0}%</small>
                    </div>` : 
                    `<span class="text-muted">${job.status === 'completed' ? '100%' : '-'}</span>`
                }
            </td>
            <td>
                <small>${createdDate}</small>
            </td>
            <td>
                <div class="btn-group btn-group-sm">
                    <button class="btn btn-outline-primary" onclick="showJobDetails('${job.id}')" title="View Details">
                        <i class="bi bi-eye"></i>
                    </button>
                    ${job.status === 'completed' ? 
                        `<button class="btn btn-outline-success" onclick="downloadResults('${job.id}')" title="Download Results">
                            <i class="bi bi-download"></i>
                        </button>` : ''
                    }
                    ${job.status !== 'running' ? 
                        `<button class="btn btn-outline-danger" onclick="deleteJob('${job.id}')" title="Delete Job">
                            <i class="bi bi-trash"></i>
                        </button>` : 
                        `<button class="btn btn-outline-warning" onclick="cancelJob('${job.id}')" title="Cancel Job">
                            <i class="bi bi-stop-circle"></i>
                        </button>`
                    }
                </div>
            </td>
        </tr>
    `;
}

function getStatusClass(status) {
    const classMap = {
        'pending': 'bg-warning text-dark',
        'running': 'bg-info text-dark',
        'completed': 'bg-success',
        'failed': 'bg-danger'
    };
    return classMap[status] || 'bg-secondary';
}

function getStatusIcon(status) {
    const iconMap = {
        'pending': 'bi bi-hourglass-split',
        'running': 'bi bi-play-circle',
        'completed': 'bi bi-check-circle',
        'failed': 'bi bi-x-circle'
    };
    return iconMap[status] || 'bi bi-question-circle';
}

async function showJobDetails(jobId) {
    try {
        const response = await fetch(`/api/jobs/${jobId}`);
        const job = await response.json();
        
        const modalContent = document.getElementById('job_details_content');
        const downloadContainer = document.getElementById('download_btn_container');
        
        modalContent.innerHTML = `
            <div class="row">
                <div class="col-md-6">
                    <h6>Job Information</h6>
                    <table class="table table-sm">
                        <tr><td><strong>Job ID:</strong></td><td><code>${job.id}</code></td></tr>
                        <tr><td><strong>Type:</strong></td><td><span class="badge bg-primary">${job.workflow_type.toUpperCase()}</span></td></tr>
                        <tr><td><strong>DEM File:</strong></td><td>${job.dem_filename}</td></tr>
                        <tr><td><strong>Status:</strong></td><td><span class="badge ${getStatusClass(job.status)}">${job.status}</span></td></tr>
                        <tr><td><strong>Progress:</strong></td><td>${job.progress || 0}%</td></tr>
                        <tr><td><strong>Created:</strong></td><td>${new Date(job.created_at).toLocaleString()}</td></tr>
                        ${job.started_at ? `<tr><td><strong>Started:</strong></td><td>${new Date(job.started_at).toLocaleString()}</td></tr>` : ''}
                        ${job.completed_at ? `<tr><td><strong>Completed:</strong></td><td>${new Date(job.completed_at).toLocaleString()}</td></tr>` : ''}
                    </table>
                </div>
                <div class="col-md-6">
                    <h6>Parameters</h6>
                    <table class="table table-sm">
                        <tr><td><strong>Time Step:</strong></td><td>${job.parameters.step} minutes</td></tr>
                        <tr><td><strong>Linke Turbidity:</strong></td><td>${job.parameters.linke_value}</td></tr>
                        <tr><td><strong>Surface Albedo:</strong></td><td>${job.parameters.albedo_value}</td></tr>
                        <tr><td><strong>CPU Threads:</strong></td><td>${job.parameters.num_threads}</td></tr>
                        ${job.workflow_type === 'eemt' ? `
                            <tr><td><strong>Start Year:</strong></td><td>${job.parameters.start_year}</td></tr>
                            <tr><td><strong>End Year:</strong></td><td>${job.parameters.end_year}</td></tr>
                        ` : ''}
                    </table>
                </div>
            </div>
            ${job.error_message ? `
                <div class="alert alert-danger mt-3">
                    <h6><i class="bi bi-exclamation-triangle"></i> Error Details</h6>
                    <pre class="mb-0">${job.error_message}</pre>
                </div>
            ` : ''}
            ${job.status === 'running' ? `
                <div class="mt-3">
                    <h6>Progress</h6>
                    <div class="progress">
                        <div class="progress-bar" style="width: ${job.progress || 0}%">
                            ${job.progress || 0}%
                        </div>
                    </div>
                </div>
            ` : ''}
        `;
        
        // Show download button if completed
        if (job.status === 'completed') {
            downloadContainer.innerHTML = `
                <button type="button" class="btn btn-success" onclick="downloadResults('${job.id}')">
                    <i class="bi bi-download"></i> Download Results
                </button>
            `;
        } else {
            downloadContainer.innerHTML = '';
        }
        
        const modal = new bootstrap.Modal(document.getElementById('jobDetailsModal'));
        modal.show();
        
    } catch (error) {
        console.error('Error loading job details:', error);
        showError('Failed to load job details');
    }
}

async function downloadResults(jobId) {
    try {
        const response = await fetch(`/api/jobs/${jobId}/results`);
        
        if (response.ok) {
            // Create download link
            const blob = await response.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `eemt_results_${jobId.substring(0, 8)}.zip`;
            a.click();
            window.URL.revokeObjectURL(url);
            
            showSuccess('Results download started');
        } else {
            const error = await response.json();
            throw new Error(error.detail || 'Download failed');
        }
        
    } catch (error) {
        console.error('Error downloading results:', error);
        showError(`Failed to download results: ${error.message}`);
    }
}

async function deleteJob(jobId) {
    // Show confirmation modal
    const modal = new bootstrap.Modal(document.getElementById('deleteModal'));
    modal.show();
    
    document.getElementById('confirm_delete').onclick = async function() {
        try {
            const response = await fetch(`/api/jobs/${jobId}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                showSuccess('Job deleted successfully');
                refreshJobs();
                modal.hide();
            } else {
                const error = await response.json();
                throw new Error(error.detail || 'Delete failed');
            }
            
        } catch (error) {
            console.error('Error deleting job:', error);
            showError(`Failed to delete job: ${error.message}`);
        }
    };
}

async function cancelJob(jobId) {
    if (!confirm('Are you sure you want to cancel this running job?')) {
        return;
    }
    
    try {
        const response = await fetch(`/api/jobs/${jobId}/cancel`, {
            method: 'POST'
        });
        
        if (response.ok) {
            showSuccess('Job cancellation requested');
            refreshJobs();
        } else {
            const error = await response.json();
            throw new Error(error.detail || 'Cancel failed');
        }
        
    } catch (error) {
        console.error('Error canceling job:', error);
        showError(`Failed to cancel job: ${error.message}`);
    }
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(function() {
        showSuccess('Job ID copied to clipboard');
    }, function(err) {
        console.error('Could not copy text: ', err);
        showError('Failed to copy to clipboard');
    });
}

function updateLastRefreshTime() {
    lastUpdateTime = new Date();
    document.getElementById('last_updated').textContent = lastUpdateTime.toLocaleTimeString();
}

function showSuccess(message) {
    showToast(message, 'success');
}

function showError(message) {
    showToast(message, 'danger');
}

function showToast(message, type) {
    // Create toast element
    const toastContainer = getOrCreateToastContainer();
    
    const toastElement = document.createElement('div');
    toastElement.className = `toast align-items-center text-white bg-${type} border-0`;
    toastElement.setAttribute('role', 'alert');
    toastElement.innerHTML = `
        <div class="d-flex">
            <div class="toast-body">${message}</div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
    `;
    
    toastContainer.appendChild(toastElement);
    
    // Show toast
    const toast = new bootstrap.Toast(toastElement, { delay: 3000 });
    toast.show();
    
    // Remove from DOM after hide
    toastElement.addEventListener('hidden.bs.toast', function() {
        toastElement.remove();
    });
}

function getOrCreateToastContainer() {
    let container = document.querySelector('.toast-container');
    if (!container) {
        container = document.createElement('div');
        container.className = 'toast-container position-fixed top-0 end-0 p-3';
        container.style.zIndex = '1200';
        document.body.appendChild(container);
    }
    return container;
}

// Global function for template usage
window.refreshJobs = refreshJobs;