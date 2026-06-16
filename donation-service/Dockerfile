FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum* ./
COPY . .
# Resolve/atualiza dependências (inclui dd-trace-go) e gera go.sum consistente.
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o donation-service .


FROM gcr.io/distroless/static:nonroot

WORKDIR /app

COPY --from=builder /app/donation-service .

EXPOSE 8082

USER nonroot:nonroot

ENTRYPOINT ["/app/donation-service"]
