CREATE OR REPLACE FUNCTION findAPAccount(INTEGER) RETURNS INTEGER STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pVendid ALIAS FOR $1;
  _accntid INTEGER;

BEGIN

  IF (NOT fetchMetricBool('InterfaceAPToGL')) THEN
    RETURN 0;
  END IF;

  SELECT apaccnt_ap_accnt_id INTO _accntid
    FROM apaccnt
    JOIN vendinfo ON (apaccnt_vendtype_id=vend_vendtype_id)
  WHERE (vend_id=pVendid);
  IF (FOUND) THEN
    RETURN _accntid;
  END IF;

  SELECT apaccnt_ap_accnt_id INTO _accntid
    FROM apaccnt
    JOIN vendtype ON (vendtype_code ~ apaccnt_vendtype)
    JOIN vendinfo ON (vend_vendtype_id=vendtype_id)
  WHERE ((apaccnt_vendtype_id=-1)
     AND (vend_id=pVendid));
  IF (FOUND) THEN
    RETURN _accntid;
  END IF;

  RETURN -1;

END;
$$ LANGUAGE 'plpgsql';
