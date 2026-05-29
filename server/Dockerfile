# Build stage
FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o server_bin main.go

# Final stage
FROM alpine:latest
RUN apk add --no-cache curl

WORKDIR /app
COPY --from=builder /app/server_bin .

EXPOSE 8080
ENTRYPOINT ["./server_bin"]
