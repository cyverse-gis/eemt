// EEMT Web Interface - Main JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Initialize the application
    initializeApp();
    loadRecentJobs();
    setupEventHandlers();
});

function initializeApp() {
    // Detect system capabilities
    detectSystemInfo();
    
    // Set up workflow type switching
    setupWorkflowTypeHandlers();
    
    // Initialize form validation
    setupFormValidation();
}

function detectSystemInfo() {
    // Detect available CPU threads
    const cpuCount = navigator.hardwareConcurrency || 4;
    
    // Safely update CPU count if element exists
    const cpuCountElement = document.getElementById('cpu_count');
    if (cpuCountElement) {
        cpuCountElement.textContent = cpuCount;
    }
    
    // Update default thread count
    const numThreadsElement = document.getElementById('num_threads');
    if (numThreadsElement) {
        numThreadsElement.value = Math.min(cpuCount, 8);
    }
    
    // Check Docker system status
    checkDockerStatus();
}

async function checkDockerStatus() {
    try {
        const response = await fetch('/api/system/status');
        const status = await response.json();
        
        const systemStatusDiv = document.getElementById('system_status');
        
        if (status.docker_available) {
            // Update status to show Docker is available
            const dockerStatusHtml = `
                <div class="d-flex justify-content-between">
                    <span>Execution Mode:</span>
                    <span class="badge bg-success">Container</span>
                </div>
                <div class="d-flex justify-content-between mt-1">
                    <span>Available Threads:</span>
                    <span id="cpu_count">${navigator.hardwareConcurrency || 4}</span>
                </div>
                <div class="d-flex justify-content-between mt-1">
                    <span>Docker:</span>
                    <span class="text-success">Available</span>
                </div>
                <div class="d-flex justify-content-between mt-1">
                    <span>EEMT Image:</span>
                    <span class="text-success small">Ready</span>
                </div>
            `;
            systemStatusDiv.innerHTML = dockerStatusHtml;
        } else {
            // Show Docker unavailable status
            const dockerStatusHtml = `
                <div class="d-flex justify-content-between">
                    <span>Execution Mode:</span>
                    <span class="badge bg-danger">Docker Required</span>
                </div>
                <div class="d-flex justify-content-between mt-1">
                    <span>Docker:</span>
                    <span class="text-danger">Unavailable</span>
                </div>
                <div class="alert alert-warning mt-2 p-2 small">
                    <strong>Setup Required:</strong><br>
                    1. Install Docker<br>
                    2. Build EEMT image:<br>
                    <code>cd docker/ubuntu/24.04 && ./build.sh</code>
                </div>
            `;
            systemStatusDiv.innerHTML = dockerStatusHtml;
            
            // Show warning on form
            showAlert('Docker container not available. Please build EEMT image first.', 'warning');
        }
        
    } catch (error) {
        console.error('Error checking Docker status:', error);
        const systemStatusDiv = document.getElementById('system_status');
        systemStatusDiv.innerHTML = `
            <div class="alert alert-danger p-2 small">
                <strong>System Check Failed</strong><br>
                Unable to verify container status
            </div>
        `;
    }
}

function setupWorkflowTypeHandlers() {
    const workflowCards = document.querySelectorAll('.workflow-card');
    const workflowRadios = document.querySelectorAll('input[name="workflow_type"]');
    const eemtParams = document.getElementById('eemt_params');
    const workflowInfo = document.getElementById('workflow_info');
    
    // Handle workflow card clicks
    workflowCards.forEach(card => {
        card.addEventListener('click', function() {
            const workflowType = this.dataset.workflow;
            const radio = document.getElementById(`workflow_${workflowType}`);
            radio.checked = true;
            
            // Update UI
            updateWorkflowSelection(workflowType);
        });
    });
    
    // Handle radio button changes
    workflowRadios.forEach(radio => {
        radio.addEventListener('change', function() {
            if (this.checked) {
                updateWorkflowSelection(this.value);
            }
        });
    });
    
    function updateWorkflowSelection(workflowType) {
        // Update card visual states
        workflowCards.forEach(card => {
            card.classList.remove('active');
            if (card.dataset.workflow === workflowType) {
                card.classList.add('active');
            }
        });
        
        // Show/hide EEMT parameters
        if (workflowType === 'eemt') {
            eemtParams.style.display = 'block';
            updateWorkflowInfo('eemt');
        } else {
            eemtParams.style.display = 'none';
            updateWorkflowInfo('sol');
        }
    }
    
    function updateWorkflowInfo(workflowType) {
        if (workflowType === 'eemt') {
            workflowInfo.innerHTML = `
                <h6>Full EEMT Workflow</h6>
                <ul class="small">
                    <li>Complete Effective Energy and Mass Transfer calculation</li>
                    <li>Integrates solar radiation with climate data (DAYMET)</li>
                    <li>Calculates topographic and traditional EEMT values</li>
                    <li>Output: EEMT maps for specified time period</li>
                </ul>
                <div class="alert alert-warning">
                    <strong>Note:</strong> EEMT workflow requires internet access for climate data download
                </div>
            `;
        } else {
            workflowInfo.innerHTML = `
                <h6>Solar Radiation Workflow</h6>
                <ul class="small">
                    <li>Calculates daily solar irradiation for entire year (365 days)</li>
                    <li>Uses GRASS GIS r.sun.mp for topographic solar modeling</li>
                    <li>Generates monthly aggregated products</li>
                    <li>Output: Global and direct solar radiation maps</li>
                </ul>
                <div class="alert alert-info">
                    <strong>Typical runtime:</strong> 5-30 minutes depending on DEM resolution and CPU threads
                </div>
            `;
        }
    }
}

function setupFormValidation() {
    const form = document.getElementById('jobForm');
    const demFile = document.getElementById('dem_file');
    const submitBtn = document.getElementById('submitBtn');
    
    // File validation
    demFile.addEventListener('change', function() {
        const file = this.files[0];
        if (file) {
            validateDemFile(file);
        }
    });
    
    function validateDemFile(file) {
        const allowedTypes = ['.tif', '.tiff'];
        const fileName = file.name.toLowerCase();
        const isValid = allowedTypes.some(ext => fileName.endsWith(ext));
        
        if (!isValid) {
            showAlert('Please select a valid GeoTIFF file (.tif or .tiff)', 'danger');
            demFile.value = '';
            return false;
        }
        
        // Check file size (warn if > 100MB)
        if (file.size > 100 * 1024 * 1024) {
            showAlert('Large DEM file detected. Processing may take significantly longer.', 'warning');
        }
        
        return true;
    }
}

function setupEventHandlers() {
    // Form submission
    document.getElementById('jobForm').addEventListener('submit', handleJobSubmission);
    
    // Immediate file upload when selected
    document.getElementById('dem_file').addEventListener('change', handleFileUpload);
    
    // Auto-refresh for recent jobs
    setInterval(loadRecentJobs, 30000); // Refresh every 30 seconds
    
    // Auto-refresh for system status
    setInterval(checkDockerStatus, 15000); // Refresh every 15 seconds
}

async function handleFileUpload(event) {
    const file = event.target.files[0];
    const uploadStatus = document.getElementById('upload_status');
    const uploadProgress = document.getElementById('upload_progress');
    const progressBar = uploadProgress.querySelector('.progress-bar');
    
    if (!file) {
        uploadStatus.textContent = 'No file selected';
        uploadStatus.className = 'text-muted small';
        uploadProgress.style.display = 'none';
        return;
    }
    
    // Validate file type
    if (!file.name.toLowerCase().endsWith('.tif') && !file.name.toLowerCase().endsWith('.tiff')) {
        uploadStatus.textContent = 'Please select a .tif or .tiff file';
        uploadStatus.className = 'text-danger small';
        uploadProgress.style.display = 'none';
        return;
    }
    
    // Show upload progress
    uploadStatus.textContent = `Uploading ${file.name}...`;
    uploadStatus.className = 'text-info small';
    uploadProgress.style.display = 'block';
    progressBar.style.width = '0%';
    
    try {
        // Create FormData for upload
        const formData = new FormData();
        formData.append('file', file);
        
        // Upload with progress tracking
        const xhr = new XMLHttpRequest();
        
        // Track upload progress
        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                const percentComplete = (e.loaded / e.total) * 100;
                progressBar.style.width = percentComplete + '%';
                progressBar.textContent = Math.round(percentComplete) + '%';
            }
        };
        
        // Handle completion
        xhr.onload = function() {
            if (xhr.status === 200) {
                const response = JSON.parse(xhr.responseText);
                uploadStatus.textContent = `✓ ${file.name} uploaded successfully`;
                uploadStatus.className = 'text-success small';
                progressBar.style.width = '100%';
                progressBar.textContent = '100%';
                
                // Store uploaded filename for job submission
                document.getElementById('dem_file').dataset.uploadedFile = response.filename || file.name;
                
                setTimeout(() => {
                    uploadProgress.style.display = 'none';
                }, 2000);
            } else {
                uploadStatus.textContent = `Upload failed: ${xhr.statusText}`;
                uploadStatus.className = 'text-danger small';
                uploadProgress.style.display = 'none';
            }
        };
        
        xhr.onerror = function() {
            uploadStatus.textContent = 'Upload failed - network error';
            uploadStatus.className = 'text-danger small';
            uploadProgress.style.display = 'none';
        };
        
        // Send the request
        xhr.open('POST', '/api/upload-file', true);
        xhr.send(formData);
        
    } catch (error) {
        console.error('Upload error:', error);
        uploadStatus.textContent = 'Upload failed - please try again';
        uploadStatus.className = 'text-danger small';
        uploadProgress.style.display = 'none';
    }
}

async function handleJobSubmission(event) {
    event.preventDefault();
    
    const form = event.target;
    const formData = new FormData(form);
    const submitBtn = document.getElementById('submitBtn');
    
    // Validate form
    if (!validateForm(form)) {
        return;
    }
    
    // Update submit button
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Submitting...';
    
    try {
        const response = await fetch('/api/submit-job', {
            method: 'POST',
            body: formData
        });
        
        const result = await response.json();
        
        if (response.ok) {
            showJobSubmissionModal(result.job_id);
            form.reset();
            // Reset workflow selection
            document.getElementById('workflow_sol').checked = true;
            updateWorkflowSelection('sol');
        } else {
            throw new Error(result.detail || 'Job submission failed');
        }
        
    } catch (error) {
        showAlert(`Error: ${error.message}`, 'danger');
    } finally {
        // Reset submit button
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<i class="bi bi-play-circle"></i> Submit Workflow';
    }
}

function validateForm(form) {
    const demFile = form.querySelector('#dem_file');
    const workflowType = form.querySelector('input[name="workflow_type"]:checked');
    
    // Check required fields
    if (!demFile.files[0]) {
        showAlert('Please select a DEM file', 'danger');
        return false;
    }
    
    if (!workflowType) {
        showAlert('Please select a workflow type', 'danger');
        return false;
    }
    
    // Validate EEMT specific fields
    if (workflowType.value === 'eemt') {
        const startYear = parseInt(form.querySelector('#start_year').value);
        const endYear = parseInt(form.querySelector('#end_year').value);
        
        if (endYear < startYear) {
            showAlert('End year must be greater than or equal to start year', 'danger');
            return false;
        }
        
        if (startYear < 1980 || endYear > 2024) {
            showAlert('Year range must be between 1980 and 2024', 'danger');
            return false;
        }
    }
    
    return true;
}

function showJobSubmissionModal(jobId) {
    const modal = new bootstrap.Modal(document.getElementById('progressModal'));
    document.getElementById('job_id_display').textContent = jobId;
    
    modal.show();
    
    // Start monitoring job progress
    monitorJobProgress(jobId);
}

async function monitorJobProgress(jobId) {
    const progressBar = document.getElementById('progress_bar');
    const statusDisplay = document.getElementById('job_status');
    
    const checkProgress = async () => {
        try {
            const response = await fetch(`/api/jobs/${jobId}`);
            const job = await response.json();
            
            // Update progress bar
            progressBar.style.width = `${job.progress}%`;
            progressBar.textContent = `${job.progress}%`;
            
            // Update status
            statusDisplay.textContent = getStatusText(job.status);
            
            // Continue monitoring if job is still running
            if (job.status === 'running' || job.status === 'pending') {
                setTimeout(checkProgress, 2000); // Check every 2 seconds
            } else if (job.status === 'completed') {
                statusDisplay.innerHTML = `
                    <div class="alert alert-success">
                        <i class="bi bi-check-circle"></i> Job completed successfully!
                        <br>Results are ready for download.
                    </div>
                `;
                loadRecentJobs(); // Refresh recent jobs
            } else if (job.status === 'failed') {
                statusDisplay.innerHTML = `
                    <div class="alert alert-danger">
                        <i class="bi bi-x-circle"></i> Job failed!
                        <br>${job.error_message || 'Unknown error occurred'}
                    </div>
                `;
            }
            
        } catch (error) {
            console.error('Error monitoring job:', error);
        }
    };
    
    checkProgress();
}

async function loadRecentJobs() {
    try {
        const response = await fetch('/api/jobs');
        const jobs = await response.json();
        
        const container = document.getElementById('recent_jobs');
        
        if (jobs.length === 0) {
            container.innerHTML = `
                <div class="text-center text-muted">
                    <i class="bi bi-hourglass-split fs-1"></i>
                    <p>No jobs submitted yet</p>
                </div>
            `;
            return;
        }
        
        // Show only last 5 jobs
        const recentJobs = jobs.slice(0, 5);
        
        container.innerHTML = recentJobs.map(job => `
            <div class="d-flex justify-content-between align-items-center border-bottom py-2">
                <div>
                    <strong>${job.workflow_type.toUpperCase()}</strong> - ${job.dem_filename}
                    <br>
                    <small class="text-muted">${new Date(job.created_at).toLocaleString()}</small>
                </div>
                <div class="text-end">
                    <span class="badge bg-${getStatusColor(job.status)}">${job.status}</span>
                    ${job.status === 'running' ? `<br><div class="progress mt-1" style="width: 100px; height: 4px;"><div class="progress-bar" style="width: ${job.progress}%"></div></div>` : ''}
                </div>
            </div>
        `).join('');
        
    } catch (error) {
        console.error('Error loading recent jobs:', error);
    }
}

function getStatusText(status) {
    const statusMap = {
        'pending': 'Waiting to start...',
        'running': 'Processing workflow...',
        'completed': 'Completed successfully',
        'failed': 'Failed with errors'
    };
    return statusMap[status] || status;
}

function getStatusColor(status) {
    const colorMap = {
        'pending': 'warning',
        'running': 'info',
        'completed': 'success',
        'failed': 'danger'
    };
    return colorMap[status] || 'secondary';
}

function showAlert(message, type = 'info') {
    // Create and show bootstrap alert
    const alertDiv = document.createElement('div');
    alertDiv.className = `alert alert-${type} alert-dismissible fade show`;
    alertDiv.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    // Insert at top of main container
    const container = document.querySelector('.container');
    container.insertBefore(alertDiv, container.firstChild);
    
    // Auto-dismiss after 5 seconds
    setTimeout(() => {
        if (alertDiv.parentNode) {
            alertDiv.remove();
        }
    }, 5000);
}