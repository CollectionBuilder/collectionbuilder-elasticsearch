
docker-build-image:
	@docker-compose build \
	--build-arg "DOCKER_USER=`id -un`" \
	--build-arg "DOCKER_UID=`id -u`" \
	--build-arg "DOCKER_GID=`id -g`" \
	default

docker-run-image:
	@docker-compose run default
