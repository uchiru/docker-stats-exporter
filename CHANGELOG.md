# docker-stats-exporter - v25 - (April 26, 2019)

* Update gems
* Add option to tail syslog file to find OOMs

# docker-stats-exporter - v24 - (August 12, 2018)

* Get docker stats using threads

# docker-stats-exporter - v23 - (August 12, 2018)

* Dont scrap containers name, just id

# docker-stats-exporter - v22 - (April 30, 2018)

* Fix 500 when stats returns nils

# docker-stats-exporter - v21 - (April 30, 2018)

* Add honey context to better error detection
* Fix 500 during cpu usage calc
* Use puma as web server
* Dont send 'SignalException: SIGTERM' exception to honeybadger

# docker-stats-exporter - v20 - (April 29, 2018)

* Extact collecting docker metrics to separate thread
* Add `docker_max_used_mem` prometheus value

# docker-stats-exporter - v19 - (April 29, 2018)

* Add `LABELS` env variable to scrape labels by white list
* Add honeybadger support
* Use puma as web server
* Use ruby image as base image

# docker-stats-exporter - v14 - 2017-06-13

* Legacy release
