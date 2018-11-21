CREATE OR REPLACE FUNCTION archiveSalesHistory(pSohistid INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN

  INSERT INTO asohist ( asohist_id,
                        asohist_cust_id,
                        asohist_itemsite_id,
                        asohist_shipdate,
                        asohist_invcdate,
                        asohist_duedate,
                        asohist_promisedate,
                        asohist_ordernumber,
                        asohist_invcnumber,
                        asohist_qtyshipped,
                        asohist_unitprice,
                        asohist_unitcost,
                        asohist_billtoname,
                        asohist_billtoaddress1,
                        asohist_billtoaddress2,
                        asohist_billtoaddress3,
                        asohist_billtocity,
                        asohist_billtostate,
                        asohist_billtozip,
                        asohist_billtocountry,
                        asohist_shiptocountry,
                        asohist_shiptoname,
                        asohist_shiptoaddress1,
                        asohist_shiptoaddress2,
                        asohist_shiptoaddress3,
                        asohist_shiptocity,
                        asohist_shiptostate,
                        asohist_shiptozip,
                        asohist_shipto_id,
                        asohist_shipvia,
                        asohist_salesrep_id,
                        asohist_misc_type,
                        asohist_misc_descrip,
                        asohist_misc_id,
                        asohist_commission,
                        asohist_commissionpaid,
                        asohist_doctype,
                        asohist_orderdate,
                        asohist_imported,
                        asohist_ponumber,
                        asohist_curr_id,
                        asohist_taxtype_id,
                        asohist_taxzone_id,
                        asohist_coitem_id,
                        asohist_invchead_id,
                        asohist_invcitem_id )
  SELECT cohist_id,
         cohist_cust_id,
         cohist_itemsite_id,
         cohist_shipdate,
         cohist_invcdate,
         cohist_duedate,
         cohist_promisedate,
         cohist_ordernumber,
         cohist_invcnumber,
         cohist_qtyshipped,
         cohist_unitprice,
         cohist_unitcost,
         cohist_billtoname,
         cohist_billtoaddress1,
         cohist_billtoaddress2,
         cohist_billtoaddress3,
         cohist_billtocity,
         cohist_billtostate,
         cohist_billtozip,
         cohist_billtocountry,
         cohist_shiptocountry,
         cohist_shiptoname,
         cohist_shiptoaddress1,
         cohist_shiptoaddress2,
         cohist_shiptoaddress3,
         cohist_shiptocity,
         cohist_shiptostate,
         cohist_shiptozip,
         cohist_shipto_id,
         cohist_shipvia,
         cohist_salesrep_id,
         cohist_misc_type,
         cohist_misc_descrip,
         cohist_misc_id,
         cohist_commission,
         cohist_commissionpaid,
         cohist_doctype,
         cohist_orderdate,
         cohist_imported,
         cohist_ponumber,
         cohist_curr_id,
         cohist_taxtype_id,
         cohist_taxzone_id,
         cohist_coitem_id,
         cohist_invchead_id,
         cohist_invcitem_id
  FROM cohist
  WHERE (cohist_id=pSohistid);

  DELETE FROM cohist
  WHERE (cohist_id=pSohistid);

  RETURN pSohistid;

END;
$$ LANGUAGE plpgsql;
