****************************************************************************************;
* Establish JHS libraries and options
****************************************************************************************;
  %include "\\rfa01\BWH-SleepEpi-jhs\Data\SAS\jhs options and libnames.sas";

***************************************************************************************;
* Read in scored Batch data from RFA
***************************************************************************************;
  proc import out=preact
    datafile="&jhspath.\actigraphy\exports\Batch\Batch_SleepScores.csv"
    DBMS=CSV REPLACE; GETNAMES=YES; DATAROW=2;
  run;

  data actdata;
    length studyid $7.;
    set preact;
    studyid = input(substr(subject,1,7),$7.);
  run;

  data actdata2;
    set actdata;
    inbeddate = In_Bed_Date;
    outbeddate = Out_Bed_Date;
    onsetdate = Onset_Date;
    inbedtime = In_Bed_Time;
    outbedtime = Out_Bed_Time;
    onsettime = Onset_Time;
    drop In_Bed_Date Out_Bed_Date Onset_Date In_Bed_Time Out_Bed_Time Onset_Time;
  run;

  *pull in data from slice export;
  data slice_in_grids;
    set jhs.jhsslice_grids;
  run;

  proc sql;
    delete
    from slice_in_grids
    where name ne "Actigraphy QS";
  quit;

  data slice_in;
    set jhs.jhsslice;
  run;

  proc sql;
    delete
    from slice_in
    where name ne "Actigraphy QS";
  quit;

  data slice_out_grids;
    set slice_in_grids;
    studyid = subject;
    drop name--creator pharynqs_breathnum--pharynqs_mbrs;
  run;

  data slice_out;
    set slice_in;
    studyid = subject;
    drop name--site Acrostic--psgqs_sleep_report feedback_ahi--feedback_activity subject;
  run;

  proc sort data=slice_out_grids;
    by studyid;
  run;

  proc sort data=slice_out;
    by studyid;
  run;

  data slice2;
    merge slice_out_grids slice_out;
    by studyid;
  run;

  data slice3;
    set slice2;

    actqs_time_started2 = input(actqs_in_time,TIME8.);
    actqs_end_time2 = input(actqs_out_time,TIME8.);
    format actqs_time_started2 actqs_end_time2 TIME8.;

    inbeddate = actqs_in_bed_date;
    outbeddate = actqs_out_bed_date;
    inbedtime = actqs_time_started2;
    outbedtime = actqs_end_time2;
    format inbeddate outbeddate MMDDYY10.;
    format inbedtime outbedtime TIME8.;

    drop actqs_recording_date actqs_date_scored actqs_date_started actqs_date_ends actqs_time_started actqs_end_time actqs_scorer_id actqs_weight actqs_in_bed_date
      actqs_out_bed_date actqs_in_time actqs_out_time actqs_end_time2 actqs_time_started2;
  run;

  proc sort data=slice3;
    by studyid inbeddate inbedtime outbeddate outbedtime;
  run;

  proc sort data=actdata2;
    by studyid inbeddate inbedtime outbeddate outbedtime;
  run;

  data actigraphy_in missing_from_slice missing_from_actigraphy;
    merge actdata2 (in=a) slice3(in=b);
    by studyid inbeddate inbedtime outbeddate outbedtime;

    if a and not b then output missing_from_slice;
    else if b and not a then output missing_from_actigraphy;
    else if a and b then output actigraphy_in;
  run;

  data pristine;
    set actigraphy_in;
  run;

  data jhs.jhsactigraphy_sleep jhs2.jhsactigraphy_sleep_&sasfiledate;
    set actigraphy_in;
    drop folder--gender actqs_date_phsy_act--actqs_excellent_day_phys_act actqs_recording_date2--actqs_end_time2;
  run;

  proc sql;
    title "Slice Data that doesn't match Actigraphy exports";
    select studyid, inbeddate, inbedtime, outbeddate, outbedtime
    from missing_from_actigraphy;
    title;

    title "Actigraphy data not found in Slice";
    select studyid, inbeddate, inbedtime, outbeddate, outbedtime
    from missing_from_slice;
    title;
  quit;

***************************************************************************************;
* READ IN SCORED REPORT FROM RFA SPACE
***************************************************************************************;
  proc import out=prephys datafile="\\rfa01\bwh-sleepepi\projects\src\jhs\data\actigraphy\exports\Batch\Batch_DailyDetailed.csv"
    DBMS=CSV REPLACE; GETNAMES=YES; DATAROW=2;
  run;

  data physdata;
    length studyid $7.;
    set prephys;
    studyid = input(substr(subject,1,7),$7.);
  run;

  data physdata2;
    set physdata;
    physdate = date;
    activitytime = Moderate + Vigorous;
  run;

  proc sql;
    delete from physdata2 where physdate = .;
  quit;

  *pull in data from slice export;
   data slice_inphys;
    set slice_in_grids;
  RUN;

  proc sql;
    delete from slice_inphys where name ne "Actigraphy QS";
  quit;

  data slice_outphys;
    set slice_inphys(rename=actqs_date_phsy_act=physdate);
    studyid = subject;
    drop name--creator actqs_row_number_sleep--pharynqs_mbqs pharynqs_mbrs;
  run;

  proc sql;
    delete from slice_outphys where physdate = .;
  quit;

  proc sort data=physdata2;
    by studyid physdate;
  run;

  proc sort data=slice_outphys;
    by studyid physdate;
  run;

  data physmerge missing_from_slicep missing_from_actp;
    merge physdata2(in=a) slice_outphys(in=b);
    by studyid physdate;
    if a and not b then output missing_from_slicep; else if b and not a then output missing_from_actp; else output physmerge;
  run;

  data pristine2;
    set physmerge;
  run;


*****************************************************************************************;
* Create permanent datasets
*****************************************************************************************;
  data jhs.jhsactigraphy_phys jhs2.jhsactigraphy_phys_&sasfiledate;
    set pristine2;

    drop age;
  run;
