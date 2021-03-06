CREATE OR REPLACE FUNCTION _packBeforeTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN
  IF TG_OP = 'INSERT' AND NEW.pack_head_id IS NOT NULL THEN
    PERFORM postComment('ChangeLog', 'S', NEW.pack_head_id, 'Added to Packing List Batch');
  END IF;

  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    IF NEW.pack_shiphead_id IS NOT NULL
	     AND NEW.pack_shiphead_id NOT IN (SELECT shiphead_id
                                          FROM shiphead
                                         WHERE shiphead_order_id = NEW.pack_head_id
                                           AND shiphead_order_type = NEW.pack_head_type)
    THEN
      RAISE EXCEPTION 'Shipment does not exist for % id % [xtuple: _packBeforeTrigger, -1, %, %]',
              NEW.pack_head_type, NEW.pack_head_id,
              NEW.pack_head_type, NEW.pack_head_id;

      RETURN OLD;
    END IF;

    IF NEW.pack_head_type = 'SO'
       AND EXISTS (SELECT true FROM cohead WHERE cohead_id = NEW.pack_head_id)
    THEN
      RETURN NEW;
    ELSEIF NEW.pack_head_type = 'TO' THEN
      IF NOT fetchMetricBool('MultiWhs') THEN
        RAISE EXCEPTION 'Transfer Orders are not supported by this version of the application [xtuple: _packBeforeTrigger, -2, %, %]',
                NEW.pack_head_type, NEW.pack_head_id;
      ELSEIF EXISTS (SELECT true FROM tohead WHERE tohead_id = NEW.pack_head_id) THEN
	      RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION '% with id % does not exist [xtuple: _packBeforeTrigger, -3, %, %]',
            NEW.pack_head_type, NEW.pack_head_id,
            NEW.pack_head_type, NEW.pack_head_id;

    RETURN OLD;
  END IF;

  -- Timestamps
  IF TG_OP = 'INSERT' THEN
    NEW.pack_head_created := now();
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.pack_head_lastupdated := now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

SELECT dropifexists('trigger', 'packBeforeTrigger');
CREATE TRIGGER packBeforeTrigger
  BEFORE INSERT OR UPDATE ON pack
  FOR EACH ROW EXECUTE PROCEDURE _packBeforeTrigger();

