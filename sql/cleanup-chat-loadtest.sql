-- Удаление данных, созданных нагрузочным тестом chat (пользователи с префиксом lt_).
-- user_sessions удаляются каскадом (ON DELETE CASCADE), но чистим явно для наглядности.
--
-- Запуск на прод-сервере (chat postgres слушает 127.0.0.1:5436, снаружи недоступен):
--   cd /opt/chat
--   docker compose exec -T postgres psql -U "$POSTGRES_USERNAME" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
--     -f - < sql/cleanup-chat-loadtest.sql
--
-- ВНИМАНИЕ: скрипт рассчитан на read-only прогон (создаются только users + user_sessions).
-- После write-тестов (чаты/сообщения/контакты) сначала удалите зависимые строки.

BEGIN;

DELETE FROM user_sessions
WHERE user_id IN (SELECT user_id FROM users WHERE username LIKE 'lt\_%');

DELETE FROM users
WHERE username LIKE 'lt\_%';

COMMIT;