all:
	docker build -t zero-jetpack . && docker run -p8000:8000 -ti --rm zero-jetpack

