# خطة التطوير المستقبلي للمزامنة

حالياً التطبيق يعمل محلياً بقاعدة SQLite.

عندما نريد تشغيله على جهاز العامل وجهاز المستخدم المستلم فعلياً، نضيف طبقة Remote Repository:

## خيار 1: Firebase

- users
- shipment_requests
- customs_records
- pricing_history

ونجعل كل سجل يحتوي:
- sync_status
- server_id
- updated_at

## خيار 2: Laravel + MySQL

نضيف API:

- POST /shipment-requests
- GET /shipment-requests?status=pending
- POST /shipment-requests/{id}/accept
- POST /shipment-requests/{id}/reject
- GET /customs-records
- PATCH /customs-records/{id}/merchant
- PATCH /customs-records/{id}/pricing

## لماذا أضفنا sync_status و server_id؟

حتى تكون قاعدة SQLite المحلية قابلة للمزامنة لاحقاً دون تغيير الجداول الأساسية.
