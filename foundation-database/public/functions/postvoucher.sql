CREATE OR REPLACE FUNCTION postvoucher(pVoheadid integer, pPostCosts boolean)
  RETURNS integer AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN
  RETURN postVoucher(pVoheadid, fetchJournalNumber('AP-VO'), pPostCosts);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION postvoucher(
    pvoheadid integer,
    pjournalnumber integer,
    ppostcosts boolean)
  RETURNS integer AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _sequence INTEGER;
  _totalAmount_base NUMERIC;
  _totalAmount NUMERIC;
  _itemAmount_base NUMERIC;
  _itemAmount NUMERIC;
  _totalDiscountableAmount NUMERIC;
  _test INTEGER;
  _taxTotal NUMERIC;
  _freightTax NUMERIC;
  _freightTotal NUMERIC;
  _freightheadtax NUMERIC;
  _accnt INTEGER;
  _a RECORD;
  _d RECORD;
  _g RECORD;
  _p RECORD;
  _r RECORD;
  _costx RECORD;
  _fdist RECORD;
  _pPostCosts BOOLEAN;
  _pExplain BOOLEAN;
  _pLowLevel BOOLEAN;
  _exchGainFreight NUMERIC;
  _taxBaseValue NUMERIC;
  _firstExchDateFreight	DATE;
  _tmpTotal		NUMERIC;
  _glDate		DATE;
  
BEGIN

  RAISE DEBUG 'postVoucher(%, %, %)', pVoheadid, pJournalNumber, pPostCosts;

  _pPostCosts := TRUE;
  _totalAmount_base := 0;
  _totalAmount := 0;
  _totalDiscountableAmount := 0;
  SELECT fetchGLSequence() INTO _sequence;

--  Cache Voucher Infomation
  SELECT vohead.*,
	 vend_number || '-' || vend_name || ' ' || vohead_reference
							  AS glnotes,
	 COALESCE(pohead_orderdate, vohead_docdate) AS pohead_orderdate,
	 COALESCE(pohead_curr_id, vohead_curr_id) AS pohead_curr_id INTO _p
  FROM vendinfo, vohead LEFT OUTER JOIN pohead ON (vohead_pohead_id = pohead_id)
  WHERE ( (vohead_id=pVoheadid)
  AND (vend_id=vohead_vend_id) )
  FOR UPDATE OF vohead;

  IF (_p.vohead_posted) THEN
    RAISE EXCEPTION 'Cannot post Voucher #% as it is already posted [xtuple: postVoucher, -10, %]',
			_p.vohead_number, _p.vohead_number;
  END IF;

  _glDate := COALESCE(_p.vohead_gldistdate, _p.vohead_distdate);

--  Disallow posting voucher if it has any voucherItems without any tagged receipts or distributions
  IF (EXISTS ( SELECT 1 
                  FROM voitem 
                 WHERE voitem_vohead_id = pVoheadId 
                   AND (NOT EXISTS(SELECT 1 
                                     FROM recv 
                                    WHERE recv_voitem_id = voitem_id 
                                      AND recv_vohead_id = voitem_vohead_id) 
                        OR NOT EXISTS(SELECT 1 
                                        FROM vodist 
                                       WHERE vodist_vohead_id = voitem_vohead_id 
                                         AND vodist_poitem_id = voitem_poitem_id )))) THEN 
    RAISE EXCEPTION 'Cannot post Voucher #% as it has items without any tagged receipts or without distributions [xtuple: postVoucher, -11, %]',
			_p.vohead_number, _p.vohead_number;
  END IF;

--  If the vohead_distdate is NULL, assume that this is a NULL vohead and quietly delete it
  IF (_p.vohead_distdate IS NULL) THEN
    DELETE FROM vohead WHERE vohead_id = pVoheadid;
    RETURN 0;
  END IF;
  IF (_p.vohead_amount <= 0) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% for a negative or zero amount (%) [xtuple: postVoucher, -1, %, %]',
			_p.vohead_number, _p.vohead_amount,
			_p.vohead_number, _p.vohead_amount;
  END IF;

-- there is no currency gain/loss on items, see issue 3892,
-- but there might be on freight, which is first encountered at p/o receipt
  SELECT recv_date::DATE INTO _firstExchDateFreight
      FROM recv
      WHERE (recv_vohead_id = pVoheadid);

  SELECT round(SUM(amount),4) INTO _tmpTotal
  FROM (
  SELECT SUM(vodist_amount) AS amount
    FROM vodist
   WHERE ( (vodist_vohead_id=pVoheadid)
     AND   (vodist_tax_id=-1) )
  UNION ALL
  SELECT (vohead_freight - vohead_freight_distributed) AS amount
    FROM vohead
   WHERE (vohead_id=pVoheadid)     
  UNION ALL
  SELECT SUM(voitem_freight) AS amount
    FROM voitem
   WHERE (voitem_vohead_id=pVoheadid)
  UNION ALL
  SELECT vohead_tax_charged
    FROM vohead
   WHERE vohead_id = pVoheadid
  ) AS data;

  IF (_tmpTotal IS NULL OR _tmpTotal <= 0) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% with negative or zero distributions (%) [xtuple: postVoucher, -2, %, %]',
			_p.vohead_number, _tmpTotal,
			_p.vohead_number, _tmpTotal;
  END IF;

  IF (_tmpTotal > _p.vohead_amount) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% with distributions greater than the voucher amount (% > %) [xtuple: postVoucher, -3, %, %, %]',
			_p.vohead_number, _tmpTotal, _p.vohead_amount,
			_p.vohead_number, _tmpTotal, _p.vohead_amount;
  END IF;

  IF (_tmpTotal < _p.vohead_amount) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% with distributions less than the voucher amount (% < %) [xtuple: postVoucher, -4, %, %, %]',
			_p.vohead_number, _tmpTotal, _p.vohead_amount,
			_p.vohead_number, _tmpTotal, _p.vohead_amount;
  END IF;

  SELECT DISTINCT poitem_linenumber INTO _test
    FROM vodist, voitem, poitem 
   WHERE ( (vodist_poitem_id=poitem_id)
     AND   (voitem_poitem_id=poitem_id)
     AND   (voitem_vohead_id=vodist_vohead_id)
     AND   ((poitem_qty_received - poitem_qty_vouchered) = 0)
     AND   (vodist_vohead_id=pVoheadid) )
   LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% as one or more of the line items have already been fully vouchered. Check P/O Line #% [postVoucher, -6, %, %]',
         _p.vohead_number, _test,
         _p.vohead_number, _test;
  END IF;

--  Start by handling taxes
  _taxTotal := getOrderTax('VCH', pVoheadid);

  SELECT COALESCE(SUM(taxdetail_tax), 0.0) INTO _freightTax
    FROM taxhead
    JOIN taxline ON taxhead_id = taxline_taxhead_id
    JOIN taxdetail ON taxline_id = taxdetail_taxline_id
   WHERE taxhead_doc_type = 'VCH'
     AND taxhead_doc_id = pVoheadid
     AND taxline_line_type = 'F';

  SELECT vohead_freight + COALESCE(SUM(voitem_freight), 0.0) INTO _freightTotal
    FROM vohead
    JOIN voitem ON vohead_id = voitem_vohead_id
   WHERE vohead_id = pVoheadid
   GROUP BY vohead_freight;

  IF (_taxTotal != 0.0) THEN
    FOR _r IN SELECT accnt,
                     COALESCE(SUM(taxdetail_tax), 0.0) *
                     GREATEST(_p.vohead_tax_charged, _taxTotal) / _taxTotal AS tax,
                     voitem_freight / COALESCE(NULLIF(_freightTotal, 0.0), 1.0) * _freightTax *
                     GREATEST(_p.vohead_tax_charged, _taxTotal) / _taxTotal AS freighttax,
                     freightaccnt
                FROM (
                      SELECT MIN(vodist_id) AS vodist_id,
                             COALESCE(costcat_purchprice_accnt_id, expcat_tax_accnt_id) AS accnt,
                             voitem_freight,
                             COALESCE(costcat_freight_accnt_id, expcat_freight_accnt_id)
                             AS freightaccnt
                        FROM vodist
                        JOIN voitem ON vodist_vohead_id = voitem_vohead_id
                                   AND vodist_poitem_id = voitem_poitem_id
                        JOIN poitem ON voitem_poitem_id = poitem_id
                        LEFT OUTER JOIN itemsite ON poitem_itemsite_id = itemsite_id
                        LEFT OUTER JOIN costcat ON itemsite_costcat_id = costcat_id
                        LEFT OUTER JOIN expcat ON poitem_expcat_id = expcat_id
                       WHERE voitem_vohead_id = pVoheadid
                       GROUP BY voitem_id, voitem_freight, costcat_purchprice_accnt_id,
                                costcat_freight_accnt_id, expcat_tax_accnt_id,
                                expcat_freight_accnt_id
                      UNION ALL
                      SELECT vodist_id,
                             COALESCE(NULLIF(vodist_accnt_id, -1), expcat_tax_accnt_id),
                             0.0,
                             NULL
                        FROM vodist
                        LEFT OUTER JOIN expcat ON vodist_expcat_id = expcat_id
                       WHERE vodist_vohead_id = pVoheadid
                         AND COALESCE(vodist_poitem_id, -1) = -1
                         AND (COALESCE(vodist_accnt_id, -1) != -1 OR
                              COALESCE(vodist_expcat_id, -1) != -1)
                     ) lines
                LEFT OUTER JOIN taxhead ON taxhead_doc_type = 'VCH'
                                       AND taxhead_doc_id = pVoheadid
                LEFT OUTER JOIN taxline ON taxhead_id = taxline_taxhead_id
                                       AND vodist_id = taxline_line_id
                LEFT OUTER JOIN taxdetail ON taxline_id = taxdetail_taxline_id
               GROUP BY vodist_id, accnt, voitem_freight, freightaccnt
    LOOP
      PERFORM insertIntoGLSeries(_sequence, 'A/P', 'VO', _p.vohead_number,
                                 _r.accnt,
                                 currToBase(_p.vohead_curr_id, _r.tax * -1, _p.vohead_docdate),
                                 _glDate, _p.glnotes);

      IF _r.freightaccnt IS NOT NULL THEN
        PERFORM insertIntoGLSeries(_sequence, 'A/P', 'VO', _p.vohead_number,
                                   _r.freightaccnt,
                                   currToBase(_p.vohead_curr_id, _r.freighttax * -1,
                                              _p.vohead_docdate),
                                   _glDate, _p.glnotes);
      END IF;
    END LOOP;

    SELECT vohead_freight / COALESCE(NULLIF(_freightTotal, 0.0), 1.0) * _freightTax *
           GREATEST(_p.vohead_tax_charged, _taxTotal) / _taxTotal,
           expcat_tax_accnt_id
      INTO _freightheadtax, _accnt
      FROM vohead
      JOIN expcat ON vohead_freight_expcat_id = expcat_id
     WHERE vohead_id = pVoheadid;

    PERFORM insertIntoGLSeries(_sequence, 'A/P', 'VO', _p.vohead_number,
                               _accnt,
                               currToBase(_p.vohead_curr_id, _freightheadtax * -1, _p.vohead_docdate),
                               _glDate, _p.glnotes);

    FOR _r IN SELECT tax_use_accnt_id,
                     currToBase(_p.vohead_curr_id, SUM(taxdetail_tax_owed), _p.vohead_docdate) AS tax
                FROM taxhead
                JOIN taxline ON taxhead_id = taxline_taxhead_id
                JOIN taxdetail ON taxline_id = taxdetail_taxline_id
                LEFT OUTER JOIN tax ON taxdetail_tax_id = tax_id
               WHERE taxhead_doc_type = 'VCH'
                 AND taxhead_doc_id = pVoheadid
               GROUP BY tax_id, tax_use_accnt_id
    LOOP
      PERFORM insertIntoGLSeries(_sequence, 'A/P', 'VO', _p.vohead_number,
                                 CASE WHEN fetchMetricText('TaxService') = 'A'
                                      THEN fetchMetricValue('AvalaraUseAccountId')::INTEGER
                                      ELSE _r.tax_use_accnt_id
                                  END,
                                 _r.tax,
                                 _glDate, _p.glnotes);
    END LOOP;
  END IF;

  _totalAmount_base := _totalAmount_base + currToBase(_p.vohead_curr_id, _p.vohead_tax_charged, _p.vohead_docdate);
  _totalAmount := _totalAmount + _p.vohead_tax_charged;

-- Update tax records with posting data
    UPDATE taxhead SET 
      taxhead_date=_p.vohead_docdate,
      taxhead_distdate=_glDate,
      taxhead_curr_id=_p.vohead_curr_id,
      taxhead_curr_rate=curr_rate,
      taxhead_journalnumber=pJournalNumber
    FROM curr_rate
    WHERE taxhead_doc_type = 'VCH'
      AND taxhead_doc_id = pVoheadId
      AND (_p.vohead_curr_id=curr_id)
      AND (_p.vohead_docdate BETWEEN curr_effective 
                           AND curr_expires);

--  Loop through the vodist records for the passed vohead that
--  are posted against a P/O Item
  FOR _g IN SELECT DISTINCT poitem_id, voitem_id, voitem_qty, poitem_expcat_id,
                            poitem_invvenduomratio, poitem_prj_id,
                            COALESCE(itemsite_id, -1) AS itemsiteid,
                            COALESCE(itemsite_costcat_id, -1) AS costcatid,
                            COALESCE(itemsite_item_id, -1) AS itemsite_item_id,
                            COALESCE(item_type, '') AS item_type,
                            (SELECT SUM(value) 
                             FROM (
                                SELECT SUM(recv_value) AS value
                                FROM recv
                                WHERE (recv_voitem_id=voitem_id)
                             UNION
                                SELECT SUM(poreject_value)*-1 AS value
                                FROM poreject
                                WHERE (poreject_voitem_id=voitem_id)) as data)
                           AS value_base,
			   (poitem_freight_received - poitem_freight_vouchered) /
			       (poitem_qty_received - poitem_qty_vouchered) * voitem_qty AS vouchered_freight,
                           currToBase(_p.pohead_curr_id,
			             (poitem_freight_received - poitem_freight_vouchered) /
		                     (poitem_qty_received - poitem_qty_vouchered) * voitem_qty,
				     _firstExchDateFreight ) AS vouchered_freight_base,
			    voitem_freight,
			    currToBase(_p.vohead_curr_id, voitem_freight,
                                       _p.vohead_distdate) AS voitem_freight_base
            FROM vodist, voitem,
                 poitem LEFT OUTER JOIN itemsite ON (poitem_itemsite_id=itemsite_id)
                        LEFT OUTER JOIN item ON (item_id=itemsite_item_id)
            WHERE ( (vodist_poitem_id=poitem_id)
             AND (voitem_poitem_id=poitem_id)
             AND (voitem_vohead_id=vodist_vohead_id)
             AND (vodist_vohead_id=pVoheadid)) LOOP

--  Grab the G/L Accounts
    IF (_g.costcatid = -1) THEN
      SELECT getPrjAccntId(_g.poitem_prj_id, pp.accnt_id) AS pp_accnt_id,
             lb.accnt_id AS lb_accnt_id,
             fr.accnt_id AS freight_accnt_id INTO _a
      FROM expcat, accnt AS pp, accnt AS lb, accnt AS fr
      WHERE ( (expcat_purchprice_accnt_id=pp.accnt_id)
       AND (expcat_liability_accnt_id=lb.accnt_id)
       AND (expcat_freight_accnt_id=fr.accnt_id)
       AND (expcat_id=_g.poitem_expcat_id) );
      IF (NOT FOUND) THEN
        RAISE EXCEPTION 'Cannot Post Voucher #% due to unassigned G/L Accounts [xtuple: postVoucher, -7, %]',
                        _p.vohead_number, _p.vohead_number;
      END IF;
    ELSE
      SELECT getPrjAccntId(_g.poitem_prj_id, costcat_purchprice_accnt_id) AS pp_accnt_id,
             getPrjAccntId(_g.poitem_prj_id, costcat_liability_accnt_id) AS lb_accnt_id,
             getPrjAccntId(_g.poitem_prj_id, costcat_freight_accnt_id) AS freight_accnt_id
      INTO _a
      FROM costcat
      WHERE (costcat_id=_g.costcatid);
      IF (NOT FOUND) THEN
        RAISE EXCEPTION 'Cannot Post Voucher #% due to unassigned G/L Accounts [xtuple: postVoucher, -8, %]',
                        _p.vohead_number, _p.vohead_number;
      END IF;
    END IF;

--  Clear the Item Amount accumulator
    _itemAmount_base := 0;
    _itemAmount := 0;

--  Figure out the total posted value for this line item
    FOR _d IN SELECT vodist_id, vodist_amount, vodist_discountable,
		     _p.vohead_curr_id, vodist_costelem_id,
		     currToBase(_p.vohead_curr_id, vodist_amount,
				_p.vohead_distdate) AS vodist_amount_base
              FROM vodist
              WHERE ( (vodist_vohead_id=pVoheadid)
               AND (vodist_poitem_id=_g.poitem_id) ) LOOP

       _pExplain := FALSE;
       SELECT * INTO _costx
         FROM itemcost
        WHERE ( (itemcost_item_id = _g.itemsite_item_id)
          AND   (itemcost_costelem_id = _d.vodist_costelem_id) );

       IF (FOUND) THEN
         _pExplain := _costx.itemcost_lowlevel;
       END IF;

--  Post the cost to the Actual if requested
--  and item type is not manufactured
--      IF ( (pPostCosts) AND (_d.vodist_costelem_id <> -1) ) THEN
      IF ( (_d.vodist_costelem_id <> -1) AND
           (_g.itemsite_item_id <> -1) AND
           (_g.item_type <> 'M') ) THEN 
        PERFORM updateCost( _g.itemsite_item_id, _d.vodist_costelem_id,
                            _pExplain, (_d.vodist_amount / (_g.voitem_qty * _g.poitem_invvenduomratio)),
			    _p.vohead_curr_id );
      END IF;

--  Add the Distribution Amount to the Item Amount
      RAISE DEBUG 'postVoucher: _d.vodist_amount=%', _d.vodist_amount;

      _itemAmount_base := _itemAmount_base + ROUND(_d.vodist_amount_base, 2);
      _itemAmount := _itemAmount + _d.vodist_amount;
      IF (_d.vodist_discountable) THEN
        _totalDiscountableAmount := (_totalDiscountableAmount + _d.vodist_amount);
      END IF;

    END LOOP;

--  Distribute from the clearing account
    PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
		_a.lb_accnt_id,
		round(_g.value_base + _g.vouchered_freight_base, 2) * -1,
		_glDate, _p.glnotes );


--  Attribute the correct portion to currency gain/loss
    _exchGainFreight := 0;
    SELECT currGain(_p.pohead_curr_id, _g.vouchered_freight,
		    _firstExchDateFreight, _p.vohead_distdate )
		    INTO _exchGainFreight;
    IF (round(_exchGainFreight, 2) <> 0) THEN
	PERFORM insertIntoGLSeries(_sequence, 'A/P', 'VO',
	    text(_p.vohead_number),
	    getGainLossAccntId(_a.lb_accnt_id), round(_exchGainFreight, 2),
	   _glDate, _p.glnotes);
    END IF;

--  Distribute the remaining variance to the Purchase Price Variance account
    IF (round(_itemAmount_base, 2) <> round(_g.value_base, 2)) THEN
      _tmpTotal := round(_itemAmount_base, 2) - round(_g.value_base, 2);
      PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
			          _a.pp_accnt_id,
			          _tmpTotal * -1,
			          _glDate, _p.glnotes );
    END IF;

--  Distribute the remaining freight variance to the Purchase Price Variance account
    IF (round(_g.voitem_freight_base + _exchGainFreight, 2) <> round(_g.vouchered_freight_base, 2)) THEN
      _tmpTotal := round(_g.voitem_freight_base + _exchGainFreight, 2) - round(_g.vouchered_freight_base, 2);
      PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
        _a.freight_accnt_id,
	      _tmpTotal * -1,
	      _glDate, _p.glnotes );
    END IF;

--  Add the distribution amount to the total amount to distribute
    RAISE DEBUG 'postVoucher: _itemAmount=%', _itemAmount;

    _totalAmount_base := (_totalAmount_base + _itemAmount_base + _g.voitem_freight_base);
    _totalAmount := (_totalAmount + _itemAmount + _g.voitem_freight);

--  Post all the Tagged Receivings for this P/O Item as Invoiced and
--  record the purchase and receive costs
--  Comment out because recv cost is set at receiving now.
    UPDATE recv
    SET recv_invoiced=TRUE,
	recv_recvcost_curr_id=basecurrid(),
        recv_recvcost=round(_g.value_base / _g.voitem_qty, 2)
    FROM poitem
    WHERE ((recv_orderitem_id=poitem_id)
      AND  (recv_order_type='PO')
      AND  (recv_orderitem_id=_g.poitem_id)
      AND  (recv_vohead_id=pVoheadid) );

--  Post all the Tagged Rejections for this P/O Item as Invoiced
    UPDATE poreject
    SET poreject_invoiced=TRUE
    WHERE ( (poreject_poitem_id=_g.poitem_id)
     AND (poreject_vohead_id=pVoheadid) );

--  Update the qty and freight vouchered fields
    UPDATE poitem
       SET poitem_qty_vouchered = (poitem_qty_vouchered + _g.voitem_qty),
           poitem_freight_vouchered = (poitem_freight_vouchered + _g.vouchered_freight)
     WHERE (poitem_id=_g.poitem_id);

  END LOOP;

--  Loop through the vodist records for the passed vohead that
--  are not posted against a P/O Item (Misc. Distributions)
--  Skip the tax distributions
  FOR _d IN SELECT vodist_id, vodist_discountable, 
		   currToBase(_p.vohead_curr_id, vodist_amount,
			      _p.vohead_distdate) AS vodist_amount_base,
		   vodist_amount,
		   vodist_accnt_id, vodist_expcat_id, vodist_costelem_id,
		   vodist_freight_vohead_id, vodist_freight_dist_method,
                   vohead_curr_id, vohead_distdate
            FROM vodist
            JOIN vohead ON vodist_vohead_id=vohead_id
            WHERE ( (vohead_id=pVoheadid)
             AND (vodist_poitem_id=-1)
             AND (vodist_tax_id=-1) ) LOOP

--  Distribute from the misc. account
    IF (_d.vodist_expcat_id > 0) THEN  -- Expense Category
      PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
			  expcat_exp_accnt_id,
			  round(_d.vodist_amount_base, 2) * -1,
			  _glDate, _p.glnotes )
         FROM expcat
        WHERE (expcat_id=_d.vodist_expcat_id);
    ELSIF (_d.vodist_costelem_id > 0) THEN  -- Freight/Duty Distribution
      FOR _fdist IN
        SELECT freightdistr_accnt_id,
                SUM(freightdistr_amount) AS freightdistr_amount
         FROM calculatefreightdistribution(_d.vodist_freight_vohead_id, _d.vodist_costelem_id,
                                           _d.vodist_freight_dist_method, _d.vodist_amount, true,
                                           _d.vohead_curr_id, _d.vohead_distdate)
        GROUP BY freightdistr_accnt_id 
      LOOP
        PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
			  _fdist.freightdistr_accnt_id,
			  round(_fdist.freightdistr_amount, 2) * -1,
			  _glDate, _p.glnotes );
      END LOOP;
      -- Cross reference freight dist voucher with original PO Voucher
      INSERT INTO docass (docass_source_type, docass_source_id, docass_target_type, docass_target_id,
                          docass_purpose, docass_username)
      VALUES ('VCH', _d.vodist_freight_vohead_id, 'VCH', pVoheadid, 'A', geteffectivextuser());
    ELSE -- G/L Account
      PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
			  _d.vodist_accnt_id,
			  round(_d.vodist_amount_base, 2) * -1,
			  _glDate, _p.glnotes );
    END IF;

--  Add the Distribution Amount to the Total Amount
    RAISE DEBUG 'postVoucher: _d.vodist_amount=%', _d.vodist_amount;

    _totalAmount_base := _totalAmount_base + ROUND(_d.vodist_amount_base, 2);
    _totalAmount := _totalAmount + _d.vodist_amount;
    IF (_d.vodist_discountable) THEN
      _totalDiscountableAmount := (_totalDiscountableAmount + _d.vodist_amount);
    END IF;

  END LOOP;

-- Post Voucher (header) Freight
  IF ((_p.vohead_freight - _p.vohead_freight_distributed) > 0) THEN
    RAISE DEBUG 'postVoucher: _p.vohead_freight=%', _p.vohead_freight;
    PERFORM insertIntoGLSeries( _sequence, 'A/P', 'VO', text(_p.vohead_number),
			  expcat_exp_accnt_id,
			  round(currtobase(_p.vohead_curr_id, _p.vohead_freight, _glDate), 2) * -1,
			  _glDate, _p.glnotes )
        FROM expcat
        WHERE (expcat_id=_p.vohead_freight_expcat_id);

    _totalAmount_base := _totalAmount_base + ROUND(currtobase(_p.vohead_curr_id, _p.vohead_freight, _glDate), 2);
    _totalAmount := _totalAmount + _p.vohead_freight;        

  END IF;  -- header freight

  SELECT insertIntoGLSeries( _sequence, 'A/P', 'VO', text(vohead_number),
                             accnt_id, round(_totalAmount_base, 2),
			     _glDate, _p.glnotes ) INTO _test
  FROM vohead LEFT OUTER JOIN accnt ON (accnt_id=findAPAccount(vohead_vend_id))
  WHERE ( (findAPAccount(vohead_vend_id)=0 OR accnt_id > 0) -- G/L interface might be disabled
    AND (vohead_id=pVoheadid) );
  IF (NOT FOUND) THEN
    RAISE EXCEPTION 'Cannot Post Voucher #% due to an unassigned A/P Account [xtuple: postVoucher, -9, %]',
                    _p.vohead_number, _p.vohead_number;
  END IF;

  PERFORM postGLSeries(_sequence, pJournalNumber);

--  Create the A/P Open Item
  RAISE DEBUG 'postVoucher: _totalAmount=%, _totalDiscountableAmount=%',
                _totalAmount, _totalDiscountableAmount;

  INSERT INTO apopen
  ( apopen_journalnumber, apopen_docdate, apopen_duedate, apopen_distdate, apopen_open,
    apopen_terms_id, apopen_vend_id, apopen_doctype,
    apopen_docnumber, apopen_invcnumber, apopen_ponumber, apopen_reference,
    apopen_amount, apopen_paid, apopen_notes, apopen_username, apopen_posted,
    apopen_curr_id, apopen_discountable_amount )
  SELECT pJournalNumber, vohead_docdate, vohead_duedate, _glDate, TRUE,
         vohead_terms_id, vohead_vend_id, 'V',
         vohead_number, vohead_invcnumber, COALESCE(TEXT(pohead_number), 'Misc.'), vohead_reference,
         round(_totalAmount, 2), 0, '', getEffectiveXtUser(), FALSE,
         vohead_curr_id, round(_totalDiscountableAmount, 2)
  FROM vohead LEFT OUTER JOIN pohead ON (vohead_pohead_id=pohead_id)
  WHERE (vohead_id=pVoheadid);

--  Close all of the P/O Items that should be closed by this Voucher
  UPDATE poitem
  SET poitem_status='C'
  FROM voitem
  WHERE ( (voitem_poitem_id=poitem_id)
   AND (voitem_close)
   AND (voitem_vohead_id=pVoheadid) );

--  Check the P/O items and if they are all closed go ahead
--  and close the P/O head.
  IF ( NOT EXISTS(SELECT 1 FROM vohead, poitem
         WHERE ((vohead_pohead_id=poitem_pohead_id)
           AND  (poitem_status<>'C')
           AND  (vohead_id=pVoheadid) ) ) ) THEN
    PERFORM closePo(vohead_pohead_id)
       FROM vohead
      WHERE (vohead_id=pVoheadid);
  END IF;

--  Set the vohead as posted
  UPDATE vohead
  SET vohead_posted=TRUE, vohead_gldistdate=_glDate
  WHERE (vohead_id=pVoheadid);

  RETURN pJournalNumber;

END;
$$ LANGUAGE plpgsql;

