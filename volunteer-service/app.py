import os
import sys
import uuid
import time
import logging
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from azure.data.tables import TableServiceClient
from azure.core.credentials import AzureNamedKeyCredential

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response

@app.route('/', defaults={'path': ''}, methods=['OPTIONS'])
@app.route('/<path:path>', methods=['OPTIONS'])
def handle_options(path):
    return '', 204

COSMOS_ENDPOINT = os.getenv("AWS_ENDPOINT_URL")      # reaproveitando secret existente
COSMOS_KEY      = os.getenv("AWS_SECRET_ACCESS_KEY")  # reaproveitando secret existente
TABLE_NAME      = os.getenv("AWS_DYNAMODB_TABLE", "volunteers")

if not COSMOS_ENDPOINT or not COSMOS_KEY:
    log.critical("AWS_ENDPOINT_URL e AWS_SECRET_ACCESS_KEY são obrigatórios (CosmosDB Table API).")
    sys.exit(1)

try:
    account_name = os.getenv("AWS_ACCESS_KEY_ID")  # reaproveitando secret: cosmos-solidarytech-f5
    credential = AzureNamedKeyCredential(account_name, COSMOS_KEY)
    service = TableServiceClient(endpoint=COSMOS_ENDPOINT, credential=credential)
    table_client = service.get_table_client(TABLE_NAME)
    log.info(f"Conectado ao CosmosDB Table API — tabela: {TABLE_NAME}")
except Exception as e:
    log.critical(f"Falha ao conectar no CosmosDB: {e}")
    sys.exit(1)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    volunteer_id = str(uuid.uuid4())
    ngo_id = str(data['ngo_id'])

    entity = {
        'PartitionKey': ngo_id,
        'RowKey': volunteer_id,
        'volunteer_id': volunteer_id,
        'name': str(data['name']),
        'email': str(data['email']),
        'ngo_id': ngo_id,
        'registered_at': str(int(time.time()))
    }

    try:
        table_client.create_entity(entity=entity)
        response = {k: v for k, v in entity.items() if k not in ('PartitionKey', 'RowKey')}
        return jsonify(response), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntário: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    try:
        entities = table_client.query_entities(f"PartitionKey eq '{ngo_id}'")
        result = [
            {k: v for k, v in e.items() if k not in ('PartitionKey', 'RowKey')}
            for e in entities
        ]
        return jsonify(result), 200
    except Exception as e:
        log.error(f"Erro ao buscar voluntários: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)
