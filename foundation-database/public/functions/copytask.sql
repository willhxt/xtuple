
DROP FUNCTION IF EXISTS copyTodoitem(INTEGER, DATE, INTEGER);

CREATE OR REPLACE FUNCTION copyTask(pParentTaskId INTEGER, pDate DATE, 
                                    pParentType TEXT DEFAULT 'TASK', pParentId INTEGER DEFAULT NULL) 
RETURNS INTEGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _duedate    DATE := COALESCE(pDate, CURRENT_DATE);
  _alarmid    INTEGER;
  _taskid INTEGER;
BEGIN
  INSERT INTO task(
            task_name,          task_number,        task_descrip,
            task_parent_type,   task_parent_id,
            task_created_by,    task_status,
            task_active,        task_due_date,
            task_notes,        
            task_owner_username,task_priority_id,
            task_recurring_task_id, task_istemplate )
    SELECT  task_name,          COALESCE(task_number, '10'),  task_descrip,
            COALESCE(pParentType, 'TASK'), pParentId,
            getEffectiveXtUser(), 'N',
            TRUE,               _duedate,
            task_notes,      
            task_owner_username,task_priority_id,
            task_recurring_task_id, false
      FROM task
     WHERE task_id = pParentTaskId
  RETURNING task_id INTO _taskid;

  IF (_taskid IS NULL) THEN
    RAISE EXCEPTION 'Error copying Task [xtuple: copytask, -10]';
  END IF;

  INSERT INTO taskass(
           taskass_task_id, taskass_username, taskass_crmrole_id,
           taskass_assigned_date)
  SELECT   _taskid, taskass_username, taskass_crmrole_id,
           CURRENT_DATE
    FROM   taskass
   WHERE   taskass_task_id = pParentTaskId;

  SELECT saveAlarm(NULL, NULL, _duedate,
                   CAST(alarm_time - DATE_TRUNC('day',alarm_time) AS TIME),
                   alarm_time_offset,
                   alarm_time_qualifier,
                   (alarm_event_recipient IS NOT NULL), alarm_event_recipient,
                   (alarm_email_recipient IS NOT NULL AND fetchMetricBool('EnableBatchManager')), alarm_email_recipient,
                   (alarm_sysmsg_recipient IS NOT NULL), alarm_sysmsg_recipient,
                   'TODO', _taskid, 'CHANGEONE')
    INTO _alarmid
    FROM alarm
   WHERE alarm_source='TODO'
     AND alarm_source_id = pParentTaskId;

   IF (_alarmid < 0) THEN
     RETURN _alarmid;
   END IF;

  RETURN _taskid;
END;
$$ LANGUAGE plpgsql;