# Build stage
FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o server_bin main.go

# Final stage
FROM alpine:latest

# Install Boundary CLI for subprocess-based tunnel management.
ARG BOUNDARY_VERSION=0.19.0
RUN apk add --no-cache curl unzip \
    && curl -fsSL "https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}/boundary_${BOUNDARY_VERSION}_linux_amd64.zip" \
       -o /tmp/boundary.zip \
    && unzip /tmp/boundary.zip -d /usr/local/bin \
    && rm /tmp/boundary.zip \
    && chmod +x /usr/local/bin/boundary

WORKDIR /app
COPY --from=builder /app/server_bin .

EXPOSE 8080
ENTRYPOINT ["./server_bin"]
