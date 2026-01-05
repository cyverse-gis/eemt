// EEMT Web Interface - Enhanced JavaScript with Real-Time Feedback

document.addEventListener('DOMContentLoaded', function() {
    console.log('EEMT: DOM loaded, initializing application...');
    // Initialize the application
    initializeApp();
    loadRecentJobs();
    setupEventHandlers();
    startSystemMonitoring();
    console.log('EEMT: Application initialization complete');
});

// Global state
let systemCheckInterval = null;
let activeWorkflowsInterval = null;
let uploadStartTime = null;
let uploadFileSize = null;

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
    
    // Update default thread count based on available cores
    const numThreadsElement = document.getElementById('num_threads');
    if (numThreadsElement) {
        // Set a reasonable default (half of available cores, max 64 for default)
        const defaultThreads = Math.min(Math.max(4, Math.floor(cpuCount / 2)), 64);
        numThreadsElement.value = defaultThreads;
        
        // Update the help text to show detected cores
        const helpText = numThreadsElement.nextElementSibling;
        if (helpText && helpText.classList.contains('form-text')) {
            helpText.innerHTML = `Number of parallel processing threads (detected: ${cpuCount} cores, max: 512)`;
        }
    }
    
    // Check Docker system status immediately
    checkDockerStatus();
}

async function checkDockerStatus() {
    const statusUpdateTime = document.getElementById('status-update-time');
    if (statusUpdateTime) {
        statusUpdateTime.textContent = 'Updating...';
    }
    
    try {
        const response = await fetch('/api/system/status');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        const status = await response.json();
        
        const systemStatusDiv = document.getElementById('system_status');
        const activeWorkflowsDiv = document.getElementById('active_workflows');
        
        if (status.docker_available) {
            // Build detailed status display
            const dockerStatusHtml = `
                <div class="system-status-grid">
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <span><i class="bi bi-server"></i> Execution Mode:</span>
                        <span class="badge bg-success">
                            <span class="status-indicator online"></span>Container Ready
                        </span>
                    </div>
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <span><i class="bi bi-cpu"></i> CPU Cores:</span>
                        <span class="fw-bold">${navigator.hardwareConcurrency || 'N/A'}</span>
                    </div>
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <span><i class="bi bi-box"></i> Docker Engine:</span>
                        <span class="text-success">
                            <i class="bi bi-check-circle-fill"></i> Running
                        </span>
                    </div>
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <span><i class="bi bi-layers"></i> EEMT Image:</span>
                        <span class="text-success small">
                            <i class="bi bi-check-circle-fill"></i> ubuntu24.04
                        </span>
                    </div>
                    ${status.active_jobs ? `
                    <div class="d-flex justify-content-between align-items-center">
                        <span><i class="bi bi-activity"></i> Active Jobs:</span>
                        <span class="badge bg-info">${status.active_jobs}</span>
                    </div>` : ''}
                </div>
            `;
            systemStatusDiv.innerHTML = dockerStatusHtml;
            
            // Show active workflows if any
            if (status.active_jobs > 0) {
                activeWorkflowsDiv.style.display = 'block';
                updateActiveWorkflows();
            } else {
                activeWorkflowsDiv.style.display = 'none';
            }
            
        } else {
            // Show Docker unavailable status with clearer instructions
            const dockerStatusHtml = `
                <div class="alert alert-danger p-2 mb-0">
                    <div class="d-flex align-items-center mb-2">
                        <i class="bi bi-exclamation-triangle-fill text-danger me-2"></i>
                        <strong>Docker Not Available</strong>
                    </div>
                    <div class="small">
                        <p class="mb-1">Container execution requires Docker. Please:</p>
                        <ol class="mb-0 ps-3">
                            <li>Install Docker Desktop</li>
                            <li>Start Docker service</li>
                            <li>Build EEMT image:<br>
                                <code class="text-nowrap">cd docker/ubuntu/24.04 && ./build.sh</code>
                            </li>
                        </ol>
                    </div>
                </div>
            `;
            systemStatusDiv.innerHTML = dockerStatusHtml;
            activeWorkflowsDiv.style.display = 'none';
            
            // Disable submit button
            const submitBtn = document.getElementById('submitBtn');
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="bi bi-x-circle"></i> Docker Required';
            }
        }
        
        // Update timestamp
        if (statusUpdateTime) {
            const now = new Date();
            statusUpdateTime.textContent = now.toLocaleTimeString();
        } else {
            console.warn('status-update-time element not found');
        }
        
    } catch (error) {
        console.error('Error checking Docker status:', error);
        const systemStatusDiv = document.getElementById('system_status');
        systemStatusDiv.innerHTML = `
            <div class="alert alert-warning p-2 mb-0">
                <i class="bi bi-exclamation-circle"></i> System check failed
                <div class="small mt-1">Unable to connect to backend service</div>
            </div>
        `;
        
        // Update timestamp even on error
        if (statusUpdateTime) {
            const now = new Date();
            statusUpdateTime.textContent = now.toLocaleTimeString();
        }
    }
}

async function updateActiveWorkflows() {
    try {
        const response = await fetch('/api/jobs?status=running');
        const activeJobs = await response.json();
        
        const listDiv = document.getElementById('active_workflows_list');
        
        if (activeJobs.length === 0) {
            listDiv.innerHTML = '<div class="text-muted small">No active workflows</div>';
            return;
        }
        
        // Display active workflows with progress
        listDiv.innerHTML = activeJobs.map(job => `
            <div class="workflow-item">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <strong>${job.workflow_type.toUpperCase()}</strong>
                        <span class="text-muted small ms-2">${job.id.substring(0, 8)}</span>
                    </div>
                    <span class="badge bg-info">${job.progress || 0}%</span>
                </div>
                <div class="workflow-progress mt-1">
                    <div class="workflow-progress-bar" style="width: ${job.progress || 0}%"></div>
                </div>
                <div class="text-muted small mt-1">
                    ${job.dem_filename} • Started ${getRelativeTime(job.started_at)}
                </div>
            </div>
        `).join('');
        
    } catch (error) {
        console.error('Error fetching active workflows:', error);
    }
}

function getRelativeTime(timestamp) {
    if (!timestamp) return 'just now';
    const date = new Date(timestamp);
    const now = new Date();
    const seconds = Math.floor((now - date) / 1000);
    
    if (seconds < 60) return 'just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
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
    
    // Validate thread count
    const numThreads = document.getElementById('num_threads');
    numThreads.addEventListener('change', function() {
        const value = parseInt(this.value);
        if (value > 512) {
            this.value = 512;
            showAlert('Maximum thread count is 512', 'warning');
        } else if (value < 1) {
            this.value = 1;
        }
    });
}

function validateDemFile(file) {
    const allowedTypes = ['.tif', '.tiff'];
    const fileName = file.name.toLowerCase();
    const isValid = allowedTypes.some(ext => fileName.endsWith(ext));
    
    if (!isValid) {
        showAlert('Please select a valid GeoTIFF file (.tif or .tiff)', 'danger');
        document.getElementById('dem_file').value = '';
        return false;
    }
    
    // Check file size and show appropriate message
    const sizeMB = file.size / (1024 * 1024);
    if (sizeMB > 500) {
        showAlert(`Very large DEM file (${sizeMB.toFixed(1)} MB). Processing may take several hours.`, 'warning');
    } else if (sizeMB > 100) {
        showAlert(`Large DEM file (${sizeMB.toFixed(1)} MB). Processing may take significantly longer.`, 'info');
    }
    
    return true;
}

function setupEventHandlers() {
    console.log('EEMT: Setting up event handlers...');
    
    // Form submission
    const jobForm = document.getElementById('jobForm');
    if (jobForm) {
        jobForm.addEventListener('submit', handleJobSubmission);
        console.log('EEMT: Job form submit handler attached');
    } else {
        console.error('EEMT: jobForm element not found!');
    }
    
    // Enhanced file upload with progress tracking
    const demFile = document.getElementById('dem_file');
    if (demFile) {
        demFile.addEventListener('change', handleFileUpload);
        console.log('EEMT: File upload change handler attached');
    } else {
        console.error('EEMT: dem_file element not found!');
    }
    
    // Auto-refresh for recent jobs
    setInterval(loadRecentJobs, 10000); // Refresh every 10 seconds
    console.log('EEMT: Event handlers setup complete');
}

function startSystemMonitoring() {
    // Initial check
    checkDockerStatus();
    
    // Set up periodic monitoring
    systemCheckInterval = setInterval(() => {
        checkDockerStatus();
    }, 15000); // Check every 15 seconds
    
    // Monitor active workflows more frequently when there are active jobs
    activeWorkflowsInterval = setInterval(() => {
        const activeWorkflowsDiv = document.getElementById('active_workflows');
        if (activeWorkflowsDiv && activeWorkflowsDiv.style.display !== 'none') {
            updateActiveWorkflows();
        }
    }, 5000); // Update every 5 seconds
}

async function handleFileUpload(event) {
    console.log('EEMT: File upload handler triggered', event);
    const file = event.target.files[0];
    console.log('EEMT: Selected file:', file ? file.name : 'none');
    
    const uploadStatus = document.getElementById('upload_status');
    const uploadProgressContainer = document.getElementById('upload_progress_container');
    const progressBar = document.getElementById('upload_progress_bar');
    const uploadDetails = document.getElementById('upload_details');
    const uploadSize = document.getElementById('upload_size');
    const uploadSpeed = document.getElementById('upload_speed');
    
    if (!file) {
        console.log('EEMT: No file selected, resetting UI');
        uploadStatus.textContent = 'No file selected';
        uploadStatus.className = 'text-center text-muted';
        uploadProgressContainer.style.display = 'none';
        uploadDetails.style.display = 'none';
        return;
    }
    
    // Validate file type
    if (!file.name.toLowerCase().endsWith('.tif') && !file.name.toLowerCase().endsWith('.tiff')) {
        uploadStatus.textContent = '⚠️ Invalid file type - Please select a .tif or .tiff file';
        uploadStatus.className = 'text-center text-danger';
        uploadProgressContainer.style.display = 'none';
        uploadDetails.style.display = 'none';
        document.getElementById('dem_file').value = '';
        return;
    }
    
    // Store file info for progress tracking
    uploadFileSize = file.size;
    uploadStartTime = Date.now();
    
    // Format file size
    const formatSize = (bytes) => {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    };
    
    // Show upload UI
    uploadStatus.textContent = `📤 Uploading: ${file.name}`;
    uploadStatus.className = 'text-center text-info';
    uploadProgressContainer.style.display = 'block';
    uploadDetails.style.display = 'block';
    uploadSize.textContent = formatSize(file.size);
    uploadSpeed.textContent = 'Calculating...';
    progressBar.style.width = '0%';
    progressBar.querySelector('.progress-text').textContent = '0%';
    
    try {
        console.log('EEMT: Starting file upload process');
        // Create FormData for upload
        const formData = new FormData();
        formData.append('file', file);
        console.log('EEMT: FormData created');
        
        // Upload with progress tracking
        const xhr = new XMLHttpRequest();
        console.log('EEMT: XMLHttpRequest created');
        
        // Track upload progress
        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                const percentComplete = Math.round((e.loaded / e.total) * 100);
                progressBar.style.width = percentComplete + '%';
                progressBar.querySelector('.progress-text').textContent = percentComplete + '%';
                
                // Calculate upload speed
                const elapsedTime = (Date.now() - uploadStartTime) / 1000; // seconds
                const uploadedBytes = e.loaded;
                const speed = uploadedBytes / elapsedTime; // bytes per second
                
                if (elapsedTime > 0) {
                    if (speed < 1024) {
                        uploadSpeed.textContent = speed.toFixed(0) + ' B/s';
                    } else if (speed < 1024 * 1024) {
                        uploadSpeed.textContent = (speed / 1024).toFixed(1) + ' KB/s';
                    } else {
                        uploadSpeed.textContent = (speed / (1024 * 1024)).toFixed(1) + ' MB/s';
                    }
                    
                    // Estimate time remaining
                    if (percentComplete < 100) {
                        const remainingBytes = e.total - e.loaded;
                        const remainingTime = remainingBytes / speed;
                        if (remainingTime < 60) {
                            uploadSpeed.textContent += ` • ${Math.round(remainingTime)}s remaining`;
                        } else {
                            uploadSpeed.textContent += ` • ${Math.round(remainingTime / 60)}m remaining`;
                        }
                    }
                }
            }
        };
        
        // Handle completion
        xhr.onload = function() {
            if (xhr.status === 200) {
                const response = JSON.parse(xhr.responseText);
                uploadStatus.innerHTML = `✅ <strong>${file.name}</strong> uploaded successfully`;
                uploadStatus.className = 'text-center text-success';
                progressBar.style.width = '100%';
                progressBar.querySelector('.progress-text').textContent = '100%';
                progressBar.classList.remove('progress-bar-animated');
                
                // Calculate final stats
                const totalTime = (Date.now() - uploadStartTime) / 1000;
                const avgSpeed = file.size / totalTime;
                uploadSpeed.textContent = `Completed in ${totalTime.toFixed(1)}s • Avg: ${formatSize(avgSpeed)}/s`;
                
                // Store uploaded filename for job submission
                document.getElementById('dem_file').dataset.uploadedFile = response.filename || file.name;
                
                // Hide progress after success
                setTimeout(() => {
                    uploadProgressContainer.style.display = 'none';
                    uploadDetails.style.display = 'none';
                }, 3000);
                
            } else {
                const errorMsg = xhr.responseText ? JSON.parse(xhr.responseText).detail : xhr.statusText;
                uploadStatus.innerHTML = `❌ Upload failed: ${errorMsg}`;
                uploadStatus.className = 'text-center text-danger';
                uploadProgressContainer.style.display = 'none';
                uploadDetails.style.display = 'none';
            }
        };
        
        xhr.onerror = function() {
            uploadStatus.innerHTML = '❌ Upload failed - Network error. Please try again.';
            uploadStatus.className = 'text-center text-danger';
            uploadProgressContainer.style.display = 'none';
            uploadDetails.style.display = 'none';
        };
        
        // Send the request
        xhr.open('POST', '/api/upload-file', true);
        xhr.send(formData);
        
    } catch (error) {
        console.error('EEMT: Upload error:', error);
        uploadStatus.innerHTML = '❌ Upload failed - Unexpected error: ' + error.message;
        uploadStatus.className = 'text-center text-danger';
        uploadProgressContainer.style.display = 'none';
        uploadDetails.style.display = 'none';
    }
}

async function handleJobSubmission(event) {
    console.log('EEMT: Job submission handler triggered');
    event.preventDefault();
    
    const form = event.target;
    const formData = new FormData(form);
    const submitBtn = document.getElementById('submitBtn');
    const modal = new bootstrap.Modal(document.getElementById('progressModal'));
    
    console.log('EEMT: Form data collected, validating...');
    
    // Validate form
    if (!validateForm(form)) {
        console.log('EEMT: Form validation failed');
        return;
    }
    
    console.log('EEMT: Form validation passed');
    
    // Show submission modal immediately
    modal.show();
    
    // Initialize submission steps UI
    const steps = {
        'validate': { element: document.getElementById('step-validate'), status: 'active' },
        'prepare': { element: document.getElementById('step-prepare'), status: 'pending' },
        'init': { element: document.getElementById('step-init'), status: 'pending' },
        'start': { element: document.getElementById('step-start'), status: 'pending' }
    };
    
    // Reset all steps
    Object.values(steps).forEach(step => {
        step.element.classList.remove('active', 'completed', 'failed');
    });
    
    const jobStatusText = document.getElementById('job_status_text');
    const jobStatusDetails = document.getElementById('job_status_details');
    const progressBar = document.getElementById('progress_bar');
    const progressText = document.getElementById('progress_text');
    
    // Function to update step status
    const updateStep = (stepId, status, message) => {
        const step = steps[stepId];
        if (step) {
            step.element.classList.remove('active', 'completed', 'failed');
            step.element.classList.add(status);
            step.status = status;
        }
        if (message) {
            jobStatusText.textContent = message;
        }
    };
    
    // Step 1: Validate
    updateStep('validate', 'active', 'Validating input file...');
    progressBar.style.width = '10%';
    progressText.textContent = '10%';
    
    // Simulate validation delay
    await new Promise(resolve => setTimeout(resolve, 500));
    updateStep('validate', 'completed', 'File validated successfully');
    
    // Step 2: Prepare container
    updateStep('prepare', 'active', 'Preparing container environment...');
    progressBar.style.width = '25%';
    progressText.textContent = '25%';
    
    // Update submit button
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Processing...';
    
    try {
        // Get the uploaded filename
        const demFileElement = document.getElementById('dem_file');
        const uploadedFilename = demFileElement.dataset.uploadedFile;
        
        if (!uploadedFilename) {
            throw new Error('No file uploaded. Please select and upload a DEM file first.');
        }
        
        // Create new FormData without the file, using uploaded filename instead
        const jobFormData = new FormData();
        jobFormData.append('workflow_type', formData.get('workflow_type'));
        jobFormData.append('uploaded_filename', uploadedFilename);
        jobFormData.append('step', formData.get('step'));
        jobFormData.append('linke_value', formData.get('linke_value'));
        jobFormData.append('albedo_value', formData.get('albedo_value'));
        jobFormData.append('num_threads', formData.get('num_threads'));
        
        // Add EEMT parameters if needed
        if (formData.get('workflow_type') === 'eemt') {
            if (formData.get('start_year')) jobFormData.append('start_year', formData.get('start_year'));
            if (formData.get('end_year')) jobFormData.append('end_year', formData.get('end_year'));
        }
        
        // Submit the job
        const response = await fetch('/api/submit-job', {
            method: 'POST',
            body: jobFormData
        });
        
        // Check content type before parsing as JSON
        const contentType = response.headers.get('content-type');
        let result;
        
        if (contentType && contentType.includes('application/json')) {
            result = await response.json();
        } else {
            // Handle non-JSON response (like HTML error pages)
            const textResponse = await response.text();
            if (!response.ok) {
                throw new Error(`Server error: ${response.status} - ${textResponse.substring(0, 100)}...`);
            }
            // If successful but not JSON, try to parse anyway
            try {
                result = JSON.parse(textResponse);
            } catch (e) {
                throw new Error(`Invalid response format: ${textResponse.substring(0, 100)}...`);
            }
        }
        
        if (response.ok) {
            // Update job ID display
            document.getElementById('job_id_display').textContent = result.job_id;
            
            updateStep('prepare', 'completed', 'Container environment ready');
            
            // Step 3: Initialize workflow
            updateStep('init', 'active', 'Initializing workflow tasks...');
            progressBar.style.width = '40%';
            progressText.textContent = '40%';
            
            // Wait a moment for initialization
            await new Promise(resolve => setTimeout(resolve, 1000));
            updateStep('init', 'completed', 'Workflow initialized');
            
            // Step 4: Start execution
            updateStep('start', 'active', 'Starting workflow execution...');
            progressBar.style.width = '50%';
            progressText.textContent = '50%';
            
            // Wait for workflow to actually start
            const workflowStarted = await waitForWorkflowStart(result.job_id);
            
            if (workflowStarted) {
                updateStep('start', 'completed', 'Workflow started successfully!');
                
                // Show success message
                jobStatusDetails.className = 'alert alert-success';
                jobStatusText.innerHTML = `
                    <i class="bi bi-check-circle"></i> Job submitted successfully!
                    <br>Job ID: <code>${result.job_id}</code>
                    <br>The workflow is now running in the background.
                `;
                
                // Start log streaming
                document.getElementById('job_log_container').style.display = 'block';
                startLogStreaming(result.job_id);
            } else {
                // Job may still be initializing
                updateStep('start', 'active', 'Workflow is initializing (this may take a moment)...');
                jobStatusDetails.className = 'alert alert-info';
                jobStatusDetails.innerHTML = `
                    <i class="bi bi-check-circle-fill"></i> <strong>Workflow is now running!</strong><br>
                    <small>Job ID: ${result.job_id}</small><br>
                    <small>You can close this window and monitor progress in the dashboard.</small>
                `;
            }
            
            // Show log container if available
            const logContainer = document.getElementById('job_log_container');
            if (logContainer) {
                logContainer.style.display = 'block';
                startLogStreaming(result.job_id);
            }
            
            // Start monitoring job progress
            monitorJobProgress(result.job_id);
            
            // Reset form
            form.reset();
            document.getElementById('workflow_sol').checked = true;
            updateWorkflowSelection('sol');
            
            // Clear file upload status and uploaded file reference
            document.getElementById('upload_status').textContent = 'No file selected';
            document.getElementById('upload_status').className = 'text-center text-muted';
            document.getElementById('dem_file').dataset.uploadedFile = '';
            
        } else {
            throw new Error(result.detail || 'Job submission failed');
        }
        
    } catch (error) {
        // Mark current step as failed
        const activeStep = Object.entries(steps).find(([_, s]) => s.status === 'active');
        if (activeStep) {
            updateStep(activeStep[0], 'failed', `Failed: ${error.message}`);
        }
        
        jobStatusDetails.className = 'alert alert-danger';
        jobStatusDetails.innerHTML = `
            <i class="bi bi-x-circle-fill"></i> <strong>Submission failed:</strong><br>
            ${error.message}
        `;
        
        progressBar.classList.remove('progress-bar-animated');
        progressBar.classList.add('bg-danger');
        
    } finally {
        // Reset submit button
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<i class="bi bi-play-circle"></i> Submit Workflow';
    }
}

async function waitForWorkflowStart(jobId, maxAttempts = 30) {
    // Enhanced workflow start monitoring with better progress tracking
    for (let i = 0; i < maxAttempts; i++) {
        try {
            const response = await fetch(`/api/jobs/${jobId}`);
            if (!response.ok) {
                console.warn(`Job status check failed: ${response.status}`);
                await new Promise(resolve => setTimeout(resolve, 1000));
                continue;
            }
            
            const job = await response.json();
            console.log(`Job ${jobId} status: ${job.status}, progress: ${job.progress}%`);
            
            // Update progress display if job is running
            if (job.status === 'running') {
                // Update progress bar in modal
                const progressBar = document.getElementById('progress_bar');
                const progressText = document.getElementById('progress_text');
                if (progressBar && progressText && job.progress > 50) {
                    progressBar.style.width = `${job.progress}%`;
                    progressText.textContent = `${job.progress}%`;
                }
                
                // Update status text
                const jobStatusText = document.getElementById('job_status_text');
                if (jobStatusText) {
                    jobStatusText.textContent = 'Workflow is running...';
                }
                
                return true;
            } else if (job.status === 'failed') {
                throw new Error(job.error_message || 'Workflow failed to start');
            } else if (job.status === 'completed') {
                return true;  // Job completed very quickly
            }
            
            // Wait before next check (increase wait time after first few attempts)
            const waitTime = i < 5 ? 1000 : 2000;
            await new Promise(resolve => setTimeout(resolve, waitTime));
            
        } catch (error) {
            console.error('Error checking job status:', error);
            if (i === maxAttempts - 1) {
                // Don't throw on last attempt, just return false
                console.warn('Timeout waiting for workflow, but job may still be initializing');
                return false;
            }
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
    }
    
    return false;
}

async function startLogStreaming(jobId) {
    const logDiv = document.getElementById('job_log');
    if (!logDiv) return;
    
    const fetchLogs = async () => {
        try {
            const response = await fetch(`/api/jobs/${jobId}/logs?tail=20`);
            if (response.ok) {
                const logs = await response.text();
                if (logs) {
                    logDiv.textContent = logs;
                    logDiv.scrollTop = logDiv.scrollHeight;
                }
            }
        } catch (error) {
            console.error('Error fetching logs:', error);
        }
    };
    
    // Fetch logs periodically
    const logInterval = setInterval(fetchLogs, 2000);
    
    // Store interval ID for cleanup
    logDiv.dataset.logInterval = logInterval;
    
    // Initial fetch
    fetchLogs();
}

function validateForm(form) {
    const demFile = form.querySelector('#dem_file');
    const workflowType = form.querySelector('input[name="workflow_type"]:checked');
    
    // Check if file was uploaded (now using uploadedFile data attribute only)
    const uploadStatus = document.getElementById('upload_status');
    if (!demFile.dataset.uploadedFile) {
        showAlert('Please select and upload a DEM file first', 'danger');
        return false;
    }
    
    // Check if upload is complete
    if (uploadStatus && uploadStatus.className.includes('text-info')) {
        showAlert('Please wait for file upload to complete', 'warning');
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
    
    // Validate thread count
    const numThreads = parseInt(form.querySelector('#num_threads').value);
    if (numThreads < 1 || numThreads > 512) {
        showAlert('Thread count must be between 1 and 512', 'danger');
        return false;
    }
    
    return true;
}

async function monitorJobProgress(jobId) {
    const progressBar = document.getElementById('progress_bar');
    const progressText = document.getElementById('progress_text');
    const jobStatusText = document.getElementById('job_status_text');
    const jobStatusDetails = document.getElementById('job_status_details');
    
    const checkProgress = async () => {
        try {
            const response = await fetch(`/api/jobs/${jobId}`);
            const job = await response.json();
            
            // Update progress bar
            const progress = Math.max(50, job.progress || 0); // Start at 50% since workflow is running
            progressBar.style.width = `${progress}%`;
            progressText.textContent = `${progress}%`;
            
            // Update status text
            if (job.status === 'running') {
                jobStatusText.textContent = `Processing... (${job.progress || 0}% complete)`;
                setTimeout(checkProgress, 2000); // Check every 2 seconds
                
            } else if (job.status === 'completed') {
                progressBar.style.width = '100%';
                progressText.textContent = '100%';
                progressBar.classList.remove('progress-bar-animated');
                progressBar.classList.add('bg-success');
                
                jobStatusDetails.className = 'alert alert-success';
                jobStatusDetails.innerHTML = `
                    <i class="bi bi-check-circle-fill"></i> <strong>Workflow completed successfully!</strong><br>
                    <small>Results are ready for download.</small>
                `;
                
                // Stop log streaming
                const logDiv = document.getElementById('job_log');
                if (logDiv && logDiv.dataset.logInterval) {
                    clearInterval(logDiv.dataset.logInterval);
                }
                
                loadRecentJobs(); // Refresh recent jobs
                
            } else if (job.status === 'failed') {
                progressBar.classList.remove('progress-bar-animated');
                progressBar.classList.add('bg-danger');
                
                jobStatusDetails.className = 'alert alert-danger';
                jobStatusDetails.innerHTML = `
                    <i class="bi bi-x-circle-fill"></i> <strong>Workflow failed!</strong><br>
                    ${job.error_message || 'Unknown error occurred'}
                `;
                
                // Stop log streaming
                const logDiv = document.getElementById('job_log');
                if (logDiv && logDiv.dataset.logInterval) {
                    clearInterval(logDiv.dataset.logInterval);
                }
            }
            
        } catch (error) {
            console.error('Error monitoring job:', error);
            // Continue monitoring even if there's an error
            setTimeout(checkProgress, 5000);
        }
    };
    
    // Start monitoring
    checkProgress();
}

async function loadRecentJobs() {
    try {
        const response = await fetch('/api/jobs?limit=5');
        const jobs = await response.json();
        
        const container = document.getElementById('recent_jobs');
        
        if (jobs.length === 0) {
            container.innerHTML = `
                <div class="text-center text-muted">
                    <i class="bi bi-inbox fs-1"></i>
                    <p>No jobs submitted yet</p>
                </div>
            `;
            return;
        }
        
        // Format jobs display with better status indicators
        container.innerHTML = jobs.map(job => {
            const statusIcon = {
                'pending': '<i class="bi bi-hourglass-split"></i>',
                'running': '<i class="bi bi-gear-fill spin"></i>',
                'completed': '<i class="bi bi-check-circle-fill"></i>',
                'failed': '<i class="bi bi-x-circle-fill"></i>'
            }[job.status] || '<i class="bi bi-question-circle"></i>';
            
            const progressBar = job.status === 'running' ? `
                <div class="progress mt-1" style="height: 4px;">
                    <div class="progress-bar progress-bar-striped progress-bar-animated" 
                         style="width: ${job.progress || 0}%"></div>
                </div>
            ` : '';
            
            return `
                <div class="d-flex justify-content-between align-items-center border-bottom py-2">
                    <div class="flex-grow-1">
                        <div class="d-flex align-items-center">
                            ${statusIcon}
                            <strong class="ms-2">${job.workflow_type.toUpperCase()}</strong>
                            <span class="text-muted small ms-2">${job.id.substring(0, 8)}</span>
                        </div>
                        <div class="small text-muted mt-1">
                            ${job.dem_filename} • ${new Date(job.created_at).toLocaleString()}
                        </div>
                        ${progressBar}
                    </div>
                    <div class="text-end">
                        <span class="badge bg-${getStatusColor(job.status)}">${job.status}</span>
                    </div>
                </div>
            `;
        }).join('');
        
    } catch (error) {
        console.error('Error loading recent jobs:', error);
    }
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
    if (container) {
        container.insertBefore(alertDiv, container.firstChild);
        
        // Auto-dismiss after 5 seconds
        setTimeout(() => {
            if (alertDiv.parentNode) {
                alertDiv.remove();
            }
        }, 5000);
    }
}

// Add spinning animation for running jobs
const style = document.createElement('style');
style.textContent = `
    @keyframes spin {
        from { transform: rotate(0deg); }
        to { transform: rotate(360deg); }
    }
    .spin {
        display: inline-block;
        animation: spin 2s linear infinite;
    }
`;
document.head.appendChild(style);