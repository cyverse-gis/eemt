---
title: Development Setup
---

# Development Environment Setup

## Overview

This guide helps you set up a complete development environment for contributing to EEMT. It covers local setup, testing frameworks, debugging tools, and best practices.

## Prerequisites

### Required Software

- **Git**: Version control (2.30+)
- **Python**: 3.12 or later
- **Docker**: 20.10+ and Docker Compose 2.0+
- **Make**: Build automation
- **VS Code** or **PyCharm**: Recommended IDEs

### Optional but Recommended

- **GRASS GIS**: 8.4+ for direct testing
- **QGIS**: 3.34 LTR for visualization
- **Jupyter**: For interactive development
- **Pre-commit**: For code quality checks

## Repository Setup

### 1. Fork and Clone

```bash
# Fork on GitHub first, then:
git clone https://github.com/YOUR_USERNAME/eemt.git
cd eemt

# Add upstream remote
git remote add upstream https://github.com/cyverse-gis/eemt.git

# Check out development branch
git checkout 2020_update
git pull upstream 2020_update
```

### 2. Branch Strategy

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Create bugfix branch
git checkout -b bugfix/issue-number-description

# Create documentation branch
git checkout -b docs/update-section-name
```

## Python Development Environment

### 1. Virtual Environment Setup

```bash
# Create virtual environment
python3 -m venv .venv

# Activate environment
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate    # Windows

# Upgrade pip
pip install --upgrade pip setuptools wheel
```

### 2. Install Dependencies

```bash
# Install runtime dependencies
pip install -r requirements.txt

# Install development dependencies
pip install -r requirements-dev.txt

# Install package in editable mode
pip install -e .

# Install pre-commit hooks
pre-commit install
```

### 3. Development Dependencies

Create `requirements-dev.txt`:

```txt
# Testing
pytest>=7.4.0
pytest-cov>=4.1.0
pytest-asyncio>=0.21.0
pytest-mock>=3.11.0
pytest-timeout>=2.1.0

# Code Quality
black>=23.0.0
flake8>=6.0.0
mypy>=1.5.0
pylint>=2.17.0
isort>=5.12.0
pre-commit>=3.3.0

# Documentation
sphinx>=7.0.0
sphinx-rtd-theme>=1.3.0
sphinx-autodoc-typehints>=1.24.0
mkdocs>=1.5.0
mkdocs-material>=9.4.0

# Debugging
ipdb>=0.13.0
ipython>=8.14.0

# Performance
line-profiler>=4.1.0
memory-profiler>=0.61.0
py-spy>=0.3.14
```

## Docker Development Environment

### 1. Build Development Container

```bash
# Build with development features
docker build -t eemt-dev -f docker/Dockerfile.dev .

# Or use docker-compose
docker-compose -f docker-compose.dev.yml build
```

### 2. Development Dockerfile

Create `docker/Dockerfile.dev`:

```dockerfile
FROM eemt:ubuntu24.04

# Install development tools
RUN apt-get update && apt-get install -y \
    vim \
    tmux \
    htop \
    gdb \
    valgrind \
    && rm -rf /var/lib/apt/lists/*

# Install Python dev dependencies
COPY requirements-dev.txt /tmp/
RUN pip install -r /tmp/requirements-dev.txt

# Enable debugging
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONASYNCIODEBUG=1

# Mount source code as volume
VOLUME /workspace
WORKDIR /workspace

# Install Jupyter for interactive development
RUN pip install jupyterlab

# Expose additional ports for debugging
EXPOSE 5678 8888

CMD ["/bin/bash"]
```

### 3. Docker Compose for Development

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  eemt-dev:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    image: eemt-dev
    container_name: eemt-dev
    volumes:
      - .:/workspace
      - grass-data:/grassdata
      - cache:/cache
    ports:
      - "5000:5000"  # Web interface
      - "5678:5678"  # Debugger
      - "8888:8888"  # Jupyter
    environment:
      - PYTHONPATH=/workspace
      - GRASS_ADDON_PATH=/workspace/grass-addons
    command: /bin/bash
    stdin_open: true
    tty: true

volumes:
  grass-data:
  cache:
```

## IDE Configuration

### VS Code

#### 1. Extensions

Install recommended extensions:

```json
// .vscode/extensions.json
{
  "recommendations": [
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-python.black-formatter",
    "ms-python.isort",
    "ms-python.flake8",
    "ms-azuretools.vscode-docker",
    "ms-vscode-remote.remote-containers",
    "charliermarsh.ruff",
    "tamasfe.even-better-toml",
    "yzhang.markdown-all-in-one"
  ]
}
```

#### 2. Settings

```json
// .vscode/settings.json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.linting.flake8Enabled": true,
  "python.formatting.provider": "black",
  "python.formatting.blackArgs": ["--line-length", "88"],
  "python.sortImports.args": ["--profile", "black"],
  "[python]": {
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.organizeImports": true
    }
  },
  "python.testing.pytestEnabled": true,
  "python.testing.unittestEnabled": false,
  "python.testing.pytestArgs": [
    "tests",
    "-v",
    "--cov=eemt",
    "--cov-report=term-missing"
  ]
}
```

#### 3. Launch Configuration

```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: Current File",
      "type": "python",
      "request": "launch",
      "program": "${file}",
      "console": "integratedTerminal",
      "justMyCode": false
    },
    {
      "name": "Python: Solar Workflow",
      "type": "python",
      "request": "launch",
      "program": "${workspaceFolder}/sol/sol/run-workflow",
      "args": [
        "--step", "15",
        "--num_threads", "2",
        "examples/mcn_10m.tif"
      ],
      "console": "integratedTerminal"
    },
    {
      "name": "Python: Debug Tests",
      "type": "python",
      "request": "launch",
      "module": "pytest",
      "args": [
        "tests",
        "-v",
        "-s"
      ],
      "console": "integratedTerminal"
    },
    {
      "name": "Docker: Attach to Container",
      "type": "python",
      "request": "attach",
      "port": 5678,
      "host": "localhost",
      "pathMappings": [
        {
          "localRoot": "${workspaceFolder}",
          "remoteRoot": "/workspace"
        }
      ]
    }
  ]
}
```

### PyCharm

#### 1. Project Setup

```bash
# Open project
pycharm .

# Configure interpreter
# File > Settings > Project > Python Interpreter
# Add > Existing Environment > .venv/bin/python
```

#### 2. Run Configurations

Create run configurations for:
- Solar workflow
- EEMT workflow
- Test suite
- Docker containers

## Testing Framework

### 1. Test Structure

```
tests/
├── unit/
│   ├── test_calculations.py
│   ├── test_solar.py
│   ├── test_climate.py
│   └── test_utils.py
├── integration/
│   ├── test_workflows.py
│   ├── test_api.py
│   └── test_docker.py
├── fixtures/
│   ├── sample_dem.tif
│   ├── climate_data.nc
│   └── expected_outputs/
├── conftest.py
└── pytest.ini
```

### 2. Writing Tests

```python
# tests/unit/test_calculations.py
import pytest
import numpy as np
from eemt import calculations

class TestEEMTCalculations:
    @pytest.fixture
    def sample_data(self):
        """Provide sample climate data."""
        return {
            'temperature': np.array([10, 15, 20, 18, 12, 8]),
            'precipitation': np.array([50, 60, 45, 40, 55, 65])
        }
    
    def test_traditional_eemt(self, sample_data):
        """Test traditional EEMT calculation."""
        result = calculations.calculate_eemt_traditional(
            temperature=sample_data['temperature'],
            precipitation=sample_data['precipitation']
        )
        
        assert 'eemt' in result
        assert 'e_bio' in result
        assert 'e_ppt' in result
        assert result['eemt'] > 0
        assert np.isfinite(result['eemt']).all()
    
    @pytest.mark.parametrize("step", [3, 15, 30])
    def test_solar_time_steps(self, step):
        """Test solar calculations with different time steps."""
        # Test implementation
        pass
```

### 3. Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=eemt --cov-report=html

# Run specific test file
pytest tests/unit/test_calculations.py

# Run with verbose output
pytest -v -s

# Run only marked tests
pytest -m "not slow"

# Run in parallel
pytest -n auto
```

### 4. Test Configuration

```ini
# pytest.ini
[tool:pytest]
minversion = 7.0
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = 
    -ra
    --strict-markers
    --cov=eemt
    --cov-branch
    --cov-report=term-missing:skip-covered
    --cov-report=html:htmlcov
    --cov-report=xml
markers =
    slow: marks tests as slow (deselect with '-m "not slow"')
    integration: integration tests
    docker: requires docker
    gpu: requires GPU
```

## Code Quality Tools

### 1. Pre-commit Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: check-added-large-files
      - id: check-merge-conflict

  - repo: https://github.com/psf/black
    rev: 23.7.0
    hooks:
      - id: black
        language_version: python3.12

  - repo: https://github.com/pycqa/isort
    rev: 5.12.0
    hooks:
      - id: isort
        args: ["--profile", "black"]

  - repo: https://github.com/pycqa/flake8
    rev: 6.1.0
    hooks:
      - id: flake8
        args: ["--max-line-length=88", "--extend-ignore=E203"]

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.5.1
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]
```

### 2. Code Formatting

```bash
# Format code with Black
black eemt/ tests/

# Sort imports
isort eemt/ tests/

# Check style
flake8 eemt/ tests/

# Type checking
mypy eemt/

# All at once with pre-commit
pre-commit run --all-files
```

## Debugging Techniques

### 1. Interactive Debugging

```python
# Using ipdb
import ipdb; ipdb.set_trace()

# Using breakpoint() (Python 3.7+)
breakpoint()

# Remote debugging with debugpy
import debugpy
debugpy.listen(5678)
debugpy.wait_for_client()
```

### 2. Logging Configuration

```python
# eemt/logging_config.py
import logging
import logging.config

LOGGING_CONFIG = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'standard': {
            'format': '%(asctime)s [%(levelname)s] %(name)s: %(message)s'
        },
        'detailed': {
            'format': '%(asctime)s [%(levelname)s] %(name)s:%(lineno)d: %(message)s'
        }
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'level': 'DEBUG',
            'formatter': 'standard',
            'stream': 'ext://sys.stdout'
        },
        'file': {
            'class': 'logging.FileHandler',
            'level': 'DEBUG',
            'formatter': 'detailed',
            'filename': 'eemt_debug.log'
        }
    },
    'loggers': {
        'eemt': {
            'level': 'DEBUG',
            'handlers': ['console', 'file'],
            'propagate': False
        }
    }
}

def setup_logging():
    logging.config.dictConfig(LOGGING_CONFIG)
```

### 3. Performance Profiling

```python
# Profile execution time
import cProfile
import pstats

profiler = cProfile.Profile()
profiler.enable()

# Run your code
workflow.run()

profiler.disable()
stats = pstats.Stats(profiler).sort_stats('cumulative')
stats.print_stats(20)

# Memory profiling
from memory_profiler import profile

@profile
def memory_intensive_function():
    # Your code here
    pass

# Line profiling
from line_profiler import LineProfiler

lp = LineProfiler()
lp_wrapper = lp(your_function)
lp_wrapper()
lp.print_stats()
```

## Continuous Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ master, 2020_update ]
  pull_request:
    branches: [ master, 2020_update ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.10', '3.11', '3.12']

    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}
    
    - name: Install system dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y grass grass-dev gdal-bin
    
    - name: Install Python dependencies
      run: |
        pip install --upgrade pip
        pip install -r requirements.txt
        pip install -r requirements-dev.txt
        pip install -e .
    
    - name: Run tests
      run: |
        pytest --cov=eemt --cov-report=xml
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml
```

## Documentation Development

### 1. Building Documentation

```bash
# MkDocs (current)
mkdocs serve  # Live development server
mkdocs build  # Build static site

# Sphinx (for API docs)
cd docs/sphinx
make html     # Build HTML docs
make livehtml # Auto-rebuild on changes
```

### 2. Writing Documentation

Follow these guidelines:
- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Cross-reference related sections
- Keep navigation logical

## Troubleshooting Development Issues

### Common Problems

1. **Import Errors**: Ensure PYTHONPATH includes project root
2. **GRASS Not Found**: Check GISBASE environment variable
3. **Docker Build Fails**: Clean Docker cache with `docker system prune`
4. **Test Failures**: Check fixture data and mock configurations

### Getting Help

- Check [existing issues](https://github.com/cyverse-gis/eemt/issues)
- Ask in [discussions](https://github.com/cyverse-gis/eemt/discussions)
- Review [contribution guidelines](contributing.md)

---

*Next: [Contributing Guidelines](contributing.md) | [Testing Guide](testing.md)*