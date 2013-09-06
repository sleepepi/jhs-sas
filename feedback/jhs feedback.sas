*program to import jackson heart study feedback data from psg and actigraphy sources;

*set options and libnames;
%include "\\rfa01\bwh-sleepepi-jhs\data\sas\jhs options and libnames.sas";
%include "\\rfa01\bwh-sleepepi-jhs\data\sas\_slice\slice import.sas";
%include "\\rfa01\bwh-sleepepi-jhs\data\sas\polysomnography\import jhs psg data.sas";

  data act_data;
    set jhs.jhsactigraphy_sleep;
  run;
  data pristine;
    set act_data;
    drop latency Total_Minutes_in_Bed Wake_After_Sleep_Onset__WASO_--Calendar_Days actqs_diary_sleep actqs_light_levels_sleep actqs_diary_b actqs_light_levels_b;
  run;

  data act_work;
    set jhs.jhsactigraphy_phys;
  run;
  data pristine2;
    set act_work;
  run;

  proc sort data=pristine2 nodupkey;
  by studyid date;
  run;
  proc sql;
    title "Physical Activity Days Missing Validity";
    select studyid, physdate
    from pristine2
    where actqs_valid_day_phys_act = .;
    title;
    delete from pristine2 where actqs_valid_day_phys_act ne 1;
  quit;

  proc sql;
    create table Physical_Averages as
      select studyid, avg(activitytime) as AvgActivity, count(actqs_valid_day_phys_act) as NumValidDay
      from pristine2
      group by studyid;
  quit;
  proc sql;
    delete from pristine where actqs_interval_type_sleep ne 1;
    create table Actigraphy_Averages as
      select studyid, avg(Total_Sleep_Time__TST_)/60 as AvgSlpTime, avg(Efficiency) as AvgEfficiency
      from pristine
      group by studyid;
  quit;

  data slicemerged;
    merge Actigraphy_averages Physical_Averages;
    by studyid;
  run;


  data psg;
    set jhs.jhspsg(rename=pptid=studyid rename=stdydt=psgdate);
    keep studyid psgdate jhsahi;
  run;

  data slice_inrec;
    set slice;
  RUN;

  proc sql;
    delete from slice_inrec where name ne "Actigraphy QS";
  quit;

  data record;
    set slice_inrec(keep=subject actqs_date_started rename=subject=studyid);
    RecStart = actqs_date_started;
    format RecStart MMDDYY10.;
    drop actqs_date_started;
  run;

  proc sort data=record;
  by studyid;
  run;
  data final;
    merge slicemerged psg record;
    by studyid;

    format RecStart MMDDYY10.;
    format AvgSlpTime jhsahi AvgEfficiency AvgActivity 10.1;
  run;

  data final;
    retain studyid psgdate jhsahi RecStart AvgSlpTime AvgEfficiency NumValidDay AvgActivity;
    set final;
  run;

  proc sql;
    title "PSG Date does not match Date Collection Started";
    select studyid, psgdate, RecStart
    from final
    where psgdate ne RecStart and RecStart ne .;
    title;
  quit;

  data jhsfeedback;
    set final;

    *only keep studies with all data;
  * if nmiss(psgdate,jhsahi,recstart,avgslptime,avgefficiency,numvalidday,avgactivity) = 0;

    rename  studyid = Subject
            jhsahi = feedback_ahi
            avgslptime = feedback_sleep_time
            avgefficiency = feedback_sleep_efficiency
            avgactivity = feedback_activity;

    keep studyid jhsahi avgslptime avgefficiency avgactivity;
  run;

  *compare to previous permanent dataset;
  proc compare base=jhs.jhsfeedback compare=jhsfeedback nomissbase transpose;
    id Subject;
  run;


  *data checking;
  title "feedback_activity > 360 -- columns probably in different order in DailyDetailed export file";
  proc sql;
    select Subject, feedback_activity
    from jhsfeedback
    where feedback_activity > 360;
  quit; title;



  *create permanent datasets;
  data jhs.jhsfeedback jhs2.jhsfeedback;
    set jhsfeedback;
  run;

  proc sort data=jhsfeedback nodupkey;
    by Subject;
  run;

  *save out csv for slice import;
  proc export data= jhsfeedback
              outfile= "\\rfa01\BWH-SleepEpi-jhs\Data\SAS\_datasets\feedback_csv\jhsfeedback_&sasfiledate..csv"
              dbms=csv replace;
       putnames=yes;
  run;

