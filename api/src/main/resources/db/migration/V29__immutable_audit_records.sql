CREATE FUNCTION reject_immutable_record_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '% records are immutable', TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER inventory_ledger_immutable
BEFORE UPDATE OR DELETE ON inventory_ledger
FOR EACH ROW EXECUTE FUNCTION reject_immutable_record_change();

CREATE TRIGGER alert_policy_audits_immutable
BEFORE UPDATE OR DELETE ON alert_policy_audits
FOR EACH ROW EXECUTE FUNCTION reject_immutable_record_change();
