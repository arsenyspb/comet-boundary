# Stage 1: Build the React Frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /app
COPY client/package*.json client/
RUN cd client && npm ci
COPY client/ client/
RUN cd client && npm run build

# Stage 2: Build the Go Backend (with embedded frontend)
FROM golang:1.26-alpine AS backend-builder
WORKDIR /app
COPY server/go.mod server/go.sum server/
RUN cd server && go mod download
COPY server/ server/
# Copy the built frontend into server/static
COPY --from=frontend-builder /app/client/dist/ /app/server/static/
RUN cd server && go build -o server_bin main.go

# Stage 3: Final Image
FROM alpine:latest
# Install Boundary CLI for subprocess-based tunnel management.
ARG BOUNDARY_VERSION=0.21.0
RUN apk add --no-cache curl unzip \
    && curl -fsSL "https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}/boundary_${BOUNDARY_VERSION}_linux_amd64.zip" \
       -o /tmp/boundary.zip \
    && unzip /tmp/boundary.zip -d /usr/local/bin \
    && rm /tmp/boundary.zip \
    && chmod +x /usr/local/bin/boundary

WORKDIR /app
COPY --from=backend-builder /app/server/server_bin .

EXPOSE 8080
ENTRYPOINT ["./server_bin"]