DROP FUNCTION IF EXISTS prjtask();
DROP FUNCTION IF EXISTS task(TEXT);

CREATE OR REPLACE FUNCTION task(pParent TEXT DEFAULT NULL) RETURNS SETOF task AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _priv TEXT;
  _grant BOOLEAN;

BEGIN
  -- This query will give us the most permissive privilege the user has been granted
  SELECT privilege, granted INTO _priv, _grant
  FROM privgranted 
  WHERE CASE WHEN pParent = 'J' THEN privilege IN ('MaintainAllProjects','ViewAllProjects','MaintainPersonalProjects','ViewPersonalProjects')
             WHEN pParent = 'TASK' THEN privilege IN ('MaintainAllToDoItems','ViewAllToDoItems','MaintainPersonalToDoItems','ViewPersonalToDoItems') 
             ELSE privilege IN ('MaintainAllProjects','ViewAllProjects','MaintainPersonalProjects','ViewPersonalProjects','MaintainAllToDoItems',
                                'ViewAllToDoItems','MaintainPersonalToDoItems','ViewPersonalToDoItems' ) END
  ORDER BY granted DESC, sequence
  LIMIT 1;

  -- If have an 'All' privilege return all results
  IF (_priv ~ 'All' AND _grant) THEN
    RETURN QUERY SELECT * FROM task;
  -- Otherwise if have any other grant, must be personal privilege.
  ELSIF (pParent = 'J' AND _grant) THEN
    RETURN QUERY
      SELECT task.* FROM task
      JOIN prj ON prj_id=task_parent_id AND task_parent_type = 'J'
      WHERE getEffectiveXtUser() IN (task_owner_username,prj_username,prj_owner_username)
        OR  task_id IN (SELECT taskass_task_id FROM taskass WHERE taskass_username = getEffectiveXtUser());
  ELSIF (_grant) THEN
    RETURN QUERY
      SELECT task.* FROM task
      WHERE (task_owner_username = getEffectiveXtUser()
          OR task_id IN (SELECT taskass_task_id FROM taskass WHERE taskass_username = getEffectiveXtUser()))
        AND CASE WHEN pParent = 'TASK' THEN task_parent_type <> 'J' ELSE true END;
  END IF;

  RETURN;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION task(TEXT) IS 'A table function that returns Task results according to privilege settings.';