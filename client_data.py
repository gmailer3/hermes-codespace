import json
from jsonschema import validate, ValidationError
from configuration.settings import settings

SCHEMA = {
    "type": "object",
    "required": ["client_id", "first_name", "last_name", "email"],
    "properties": {
        "client_id": {"type": "string", "pattern": r"^[A-Za-z0-9_\-]+$"},
        "first_name": {"type": "string", "minLength": 1},
        "last_name": {"type": "string", "minLength": 1},
        "email": {"type": "string", "pattern": r"^[^@\s]+@[^@\s]+\.[^@\s]+$"},
        "phone": {"type": "string"}, "address": {"type": "string"},
        "username": {"type": "string"}, "additional_information": {"type": "object"},
    },
}

class InvalidClientData(Exception): ...

def load_client(filename: str) -> dict:
    p = (settings.root / "client_data" / filename).resolve()
    if p.parent != (settings.root / "client_data").resolve():
        raise InvalidClientData("path traversal blocked")
    if p.stat().st_size > 1_000_000:
        raise InvalidClientData("file too large")
    data = json.loads(p.read_text())
    try: validate(data, SCHEMA)
    except ValidationError as e: raise InvalidClientData(e.message)
    return data
