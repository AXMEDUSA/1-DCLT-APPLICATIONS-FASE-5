FROM golang:1.21-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o donation-service .


FROM gcr.io/distroless/static:nonroot

WORKDIR /app

COPY --from=builder /app/donation-service .

EXPOSE 8082

USER nonroot:nonroot

ENTRYPOINT ["/app/donation-service"]
