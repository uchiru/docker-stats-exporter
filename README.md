# docker-stats-exporter

Simple docker stats exporter

```
docker build -t ds .
docker run -it -p9292:9292 -v /var/run/docker.sock:/var/run/docker.sock ds rackup -o 0.0.0.0
```
