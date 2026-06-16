module donation-service

go 1.24.0

require (
	github.com/aws/aws-sdk-go v1.51.10
	github.com/jackc/pgx/v4 v4.18.3
	github.com/joho/godotenv v1.5.1
	gopkg.in/DataDog/dd-trace-go.v1 v1.71.0
)

// Força versão mínima da grpc-go para mitigar CVE-2026-33186
// (Authorization bypass via HTTP/2 path validation). Trazida transitivamente
// pelo dd-trace-go. Pode ser revisada quando dd-trace-go atualizar.
require google.golang.org/grpc v1.79.3

// Força versão mínima do OpenTelemetry para mitigar CVE-2026-29181
// (DoS via crafted multi-value baggage headers). Também transitiva via dd-trace-go.
require go.opentelemetry.io/otel v1.41.0

require (
	github.com/jackc/chunkreader/v2 v2.0.1 // indirect
	github.com/jackc/pgconn v1.14.3 // indirect
	github.com/jackc/pgio v1.0.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgproto3/v2 v2.3.3 // indirect
	github.com/jackc/pgservicefile v0.0.0-20221227161230-091c0ba34f0a // indirect
	github.com/jackc/pgtype v1.14.0 // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	golang.org/x/crypto v0.35.0 // indirect
	golang.org/x/text v0.22.0 // indirect
)
