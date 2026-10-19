platform = linux/amd64
repo = harbor.example.edu/batch/cloudshell-batch
tag = 24.04
repotag = $(repo):$(tag)

build:
	docker buildx build --rm --platform "$(platform)" -t "$(repotag)" .

push:
	docker push "$(repotag)"

test: build
	./test.sh "$(repotag)"

rmi:
	docker rmi "$(repotag)"
