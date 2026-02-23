-- ============================================================================
-- REPORT CONTENT — Server-side report insertion
-- ============================================================================
-- Auto-sets reporter_id from auth.uid() so the client only needs to send
-- the target type, target ID, and reason.
-- Prevents duplicate reports from the same user for the same target.
-- ============================================================================

CREATE OR REPLACE FUNCTION report_content(
    p_target_type TEXT,
    p_target_id UUID,
    p_reason TEXT
)
RETURNS VOID AS $$
DECLARE
    v_reporter UUID := auth_uid();
BEGIN
    IF v_reporter IS NULL THEN
        RAISE EXCEPTION 'unauthorized: Must be signed in to report content';
    END IF;

    -- Prevent duplicate reports from the same user for the same target
    IF EXISTS (
        SELECT 1 FROM reports
        WHERE reporter_id = v_reporter
          AND target_id = p_target_id
    ) THEN
        -- Silently succeed — user already reported this content
        RETURN;
    END IF;

    INSERT INTO reports (reporter_id, target_type, target_id, reason)
    VALUES (v_reporter, p_target_type::report_target_type, p_target_id, p_reason);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
