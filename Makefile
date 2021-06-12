
build-docker-image:
	@docker-compose build \
	--build-arg "DOCKER_USER=`id -un`" \
	--build-arg "DOCKER_UID=`id -u`" \
	--build-arg "DOCKER_GID=`id -g`" \
	default

run-docker-image:
	@docker-compose run default
