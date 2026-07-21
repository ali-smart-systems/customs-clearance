PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('worker', 'manager')),
  created_at TEXT NOT NULL
);

CREATE TABLE shipment_requests (
  id TEXT PRIMARY KEY,
  worker_id TEXT NOT NULL,
  agent_name TEXT NOT NULL,
  driver_name TEXT NOT NULL,
  plate_number TEXT NOT NULL,
  quantity REAL NOT NULL CHECK(quantity > 0),
  status TEXT NOT NULL CHECK(status IN ('pending', 'accepted', 'rejected')),
  created_at TEXT NOT NULL,
  reviewed_by TEXT,
  reviewed_at TEXT,
  reject_reason TEXT,
  sync_status TEXT NOT NULL DEFAULT 'local',
  server_id TEXT,
  FOREIGN KEY(worker_id) REFERENCES users(id),
  FOREIGN KEY(reviewed_by) REFERENCES users(id)
);

CREATE TABLE customs_records (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  agent_name TEXT NOT NULL,
  driver_name TEXT NOT NULL,
  plate_number TEXT NOT NULL,
  quantity REAL NOT NULL CHECK(quantity > 0),
  customs_amount REAL NOT NULL DEFAULT 0,
  beneficiary_merchant TEXT,
  pricing_unit TEXT,
  unit_price REAL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'local',
  server_id TEXT,
  FOREIGN KEY(request_id) REFERENCES shipment_requests(id)
);

CREATE TABLE pricing_history (
  id TEXT PRIMARY KEY,
  customs_record_id TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit TEXT NOT NULL,
  unit_price REAL NOT NULL,
  customs_amount REAL NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(customs_record_id) REFERENCES customs_records(id)
);

CREATE INDEX idx_shipment_requests_status ON shipment_requests(status);
CREATE INDEX idx_shipment_requests_created_at ON shipment_requests(created_at);
CREATE INDEX idx_customs_records_agent_name ON customs_records(agent_name);
CREATE INDEX idx_customs_records_created_at ON customs_records(created_at);
