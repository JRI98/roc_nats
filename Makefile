run:
	@docker rm -f nats-roc-dev >/dev/null 2>&1 || true
	CID=$$(docker run -d --rm --name nats-roc-dev -p 4222:4222 nats:latest) && \
	trap "docker rm -f $$CID >/dev/null 2>&1" EXIT INT TERM && \
	roc main.roc
