# Development

Build from the Dockerfile in this folder:

```
sudo docker build --network=host -t tswetnam/eemt:latest .
```

# Usage

Pull from DockerHub:

```
docker pull tswetnam/eemt:latest .
```

Run as a Jupyter Lab

```
docker run -it --rm -p 8888:8888 tswetnam/eemt:latest 
```
