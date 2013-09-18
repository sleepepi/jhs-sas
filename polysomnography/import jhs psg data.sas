****************************************************************************************;
* Establish JHS libraries and options
****************************************************************************************;
  %include "\\rfa01\BWH-SleepEpi-jhs\Data\SAS\jhs options and libnames.sas";

***************************************************************************************;
* Establish temporary network drive
***************************************************************************************;
  x net use y: /d;
  x net use y: "\\rfa01\BWH-SleepEpi-jhs\Data\PSG" /P:No;

***************************************************************************************;
* Create input statement file based on PSG report variables
***************************************************************************************;
  proc import out=reportvars
      datafile = "&jhspath.\SAS\polysomnography\jhs psg report variables.csv"
      dbms = csv
      replace;
      guessingrows=1000;
    getnames = yes;
  run;

  *output statements to new file;
  data _null_;
    file "&jhspath.\SAS\polysomnography\jhs psg input statement.sas";
    put "input";
  run;

  data _null_;
    file "&jhspath.\SAS\polysomnography\jhs psg input statement.sas" MOD;
    set reportvars;
    length out $32000.;
    out = strip(input_code) || " " || strip(Input_Code_2);
    put out;
  run;
  data _null_;
    file "&jhspath.\SAS\polysomnography\jhs psg input statement.sas" MOD;
    put ";";
  run;

  *create recode file;
  data _null_;
    file "&jhspath.\SAS\polysomnography\jhs psg variable recodes.sas";
    set reportvars;
    length out $32000.;
    out = strip(conversion_code) || "  " || strip(formatting_code) || " " || strip(drop_input_variable);
    put out;
  run;



***************************************************************************************;
* Read in scored reports from raw data
***************************************************************************************;
  * get list of directories in scored folder;
  filename f1 pipe 'dir "y:\SAS Reports" /b';

  * within each directory, read in report file named s + foldername + .txt;
  data jhsfiles;
    infile f1 truncover;
    input filename $30.;
    length foldername $150.;
    foldername = "y:\SAS Reports\" || strip(filename);
    foldername = lowcase(foldername);
    filename = lowcase(filename);
    if strip(filename) in ("","_CMPStudyList.mdb") then delete;
  run;

  proc sort data=jhsfiles;
    by filename;
  run;

  data jhsreports;
    set jhsfiles;
    by filename;
  run;

  data pro2_in;
    set jhsreports;

    infile dummy filevar=foldername end=done truncover lrecl=256 N=78;
    do while(not done);
      * include input statement;
      %include "&jhspath.\SAS\polysomnography\jhs psg input statement.sas";

      * recode mising value codes to system missing;
      array char{*} _character_;
      do i=1 to dim(char);
        if char{i} = "N/A" then char{i}= "";
        if char{i} = "-" then char{i} = "";
        * round 30sec to nearest minute;
        if char{i} = "30sec" then char{i} = '00:01';
      end;

    end;
    call symput('nread',_n_);
  run;


*******************************************************************************;
* Disconnect network drive;
*******************************************************************************;
  x net use y: /delete /y;


*******************************************************************************;
* ASSIGN VARIABLE FORMATS AND RECODE CHARACTER TO NUMERIC
*******************************************************************************;

  data check1;
    set pro2_in;
    pptid = upcase(pptid_in);
    stdydt = input(substr(filename,13,8),mmddyy8.);
  run;

  proc sort data=check1;
    by pptid stdydt;
  run;

  data check1;
    merge check1 (in=a);
    by pptid stdydt;
    if a and index(scorerid_in,"/")>0;
  run;

  *print from check1;
  proc sql;
    title "JHS PSG: Possibly incorrect/improper Scorer ID, will be excluded from dataset";
    select filename, scorerid_in
    from check1; title;
  quit;

  data check2;
    set pro2_in;
    if index(stdatep_in,":")>0
      or index(scoredt_in,":")>0
      or index(stloutp_in,":")=0
      or index(stonsetp_in,":")=0
      or index(slplatp_in,":")=0
      or index(remlaip_in,":")=0
      or index(remlaiip_in,":")=0
      or index(timebedp_in,":")=0
      or index(slpprdp_in,":")=0
      or index(slpeffp_in,":")>0
      or index(minstg1p_in,":")=0
      or index(minstg2p_in,":")=0
      or index(mnstg34p_in,":")=0
      or index(minremp_in,":")=0
      ;
  run;

  *print from check2;
  proc sql;
    title "JHS PSG: Possibly improperly formatted report, will be excluded from dataset";
    select filename, scorerid_in, STDATEP_in, SCOREDT_in
    from check2; title;
  quit;

  proc sql;
    create table pro2_valid as
    select * from pro2_in
    where filename not in (select filename from check1)
      and filename not in (select filename from check2);
  quit;

  data pro2;
    set pro2_valid;
    drop i;
    * include code to recode and format variables;
    %include "&jhspath.\SAS\polysomnography\jhs psg variable recodes.sas";

    * store the number of records read in from the network to report later for easy checking;
    call symput('filecount2',_n_);

    drop filename;
  run;


*****************************************************************************************;
* Format PPTID variable and sort
*****************************************************************************************;
  data jhs_in jhs_error;
    length pptid $20. stdydt 8. pptid_full $20.;
    set pro2;

    pptid_full = pptid;
    pptid = substr(pptid,1,7);
    stdydt = stdatep;
    format stdydt mmddyy10.;

    if pptid = "" then output jhs_error;
    else output jhs_in;

  run;

  proc sort data=jhs_in;
    by pptid stdydt;
  run;


*****************************************************************************************;
* Import sleep quality data from Slice dataset;
*****************************************************************************************;
  data psgqs_in;
    length pptid $7. stdydt 8.;
    set jhs.jhsslice;

    pptid = Subject;
    stdydt = psgqs_recording_date;
    format stdydt mmddyy10.;

    if name = 'Polysomnography QS' and Status = 'valid';
    keep pptid stdydt psgqs_recording_date -- psgqs_sleep_report;
  run;

  proc sort data=psgqs_in out=psgqs;
    by pptid stdydt;
  run;


*****************************************************************************************;
* Merge PSG and QS datasets
*****************************************************************************************;
  data jhsmerge;
    length pptid $7. stdydt hasqs hastxt 8.;
    merge psgqs (in=qs) jhs_in (in=txt);
    by pptid stdydt;

    if qs then hasqs = 1;
    if txt then hastxt = 1;
  run;

  proc sort data=jhsmerge;
    by pptid stdydt;
  run;

  data jhspsg;
    set jhsmerge;
    by pptid stdydt;

  if hastxt = 1 then do;

  ************************************************************************************;
  * #1 WAKE TIME AFTER SLEEP ONSET
  ************************************************************************************;
    waso = timebedp - slpprdp - slplatp;

  ************************************************************************************;
  * #2 TOTAL SLEEP PERIOD VARIABLES
  ************************************************************************************;
    time_bed = timebedp;

  ************************************************************************************;
  * #4 SLEEP EFFICIENCY
  ************************************************************************************;
    if timebedp ne 0 then do;
        slp_eff = 100*(slpprdp)/timebedp;
    end;

  ************************************************************************************;
  * #5 TIME AND PERCENT IN EACH SLEEP STAGE
  * for all, exclude studies scored as sleep/wake;
  * for stage 1, exclude studies with problems scoring sleep/wake or stg1/stg2;
  * for stage 2, exclude studies with problems scoring stg1/stg2 or stg2/stg3;
  * for stage 3, exclude studies with problems scoring stg3/stg4;
  * for REM, exclude studies with problems scoring rem/nrem;
  ************************************************************************************;
      * STAGE 1;
      timest1p = tmstg1p;
      timest1 = minstg1p;
      * STAGE 2;
      timest2p = tmstg2p;
      timest2 = minstg2p;
      * STAGE 3/4;
      times34p = tmstg34p;
      timest34= mnstg34p;
      * REM;
      timeremp = tmremp;
      timerem = minremp;

  ************************************************************************************;
  * #6 REM LATENCY
  * exclude studies scored as sleep/wake or where scoring rem/non-rem is unreliable;
  ************************************************************************************;
        rem_lat1 = remlaip;

  ************************************************************************************;
  * #7 PERCENT OF SLEEP TIME SUPINE AND NON-SUPINE
  ************************************************************************************;
      if slpprdp gt 0 then do;
        supinep = 100*(remepbp+nremepbp)/(remepbp+nremepbp+remepop+nremepop);
        nsupinep = 100*(remepop+nremepop)/(remepbp+nremepbp+remepop+nremepop);
      end;

  ************************************************************************************;
  * #8 AROUSAL INDEX (ALL, NREM, REM)
  * For all, exclude studies scored as sleep/wake or where arousals were ignored or
  *   if total sleep time is zero;
  * For ai by rem stage, exclude studies where rem/nrem scoring unreliable;
  * For ai in rem, exclude studies where time in rem is zero;
  ************************************************************************************;
    if slpprdp ne 0 then do;
      * OVERALL AROUSAL INDEX;
        ai_all = 60*(arrembp + arremop +arnrembp +arnremop) / slpprdp;

      * AI IN REM;
      if minremp ne 0 then do;
        ai_rem = 60*(arrembp + arremop) / minremp;
      end;

      * AI IN NON-REM;
      ai_nrem = 60*(arnrembp +arnremop) / (slpprdp - minremp);
    end;

  ************************************************************************************;
  * #9 RDI
  * RDI at specified desat
      [ (Total number of central apneas at specified desat)
      + (Total number of obstructive apneas at specified desat)
      + (hypopneas at specified desat)]
      / (hours of sleep)
  * For all, exclude if total sleep time is zero;
  * For Profusion2 studies, include AASM hypopneas ('unsure events');
  ************************************************************************************;
    if slpprdp gt 0 then do;
      rdi0p = 60*(hrembp + hrop + hnrbp + hnrop +
            carbp + carop + canbp + canop +
            oarbp + oarop + oanbp +oanop +
            urbp + urop + unrbp + unrop) / slpprdp;
        rdi2p = 60*(hrembp2 + hrop2 + hnrbp2 + hnrop2 +
            carbp2 + carop2 + canbp2 + canop2 +
            oarbp2 + oarop2 + oanbp2 +oanop2 +
            urbp2 + urop2 + unrbp2 + unrop2) / slpprdp;
        rdi3p = 60*(hrembp3 + hrop3 + hnrbp3 + hnrop3 +
            carbp3 + carop3 + canbp3 + canop3 +
            oarbp3 + oarop3 + oanbp3 + oanop3 +
            urbp3 + urop3 + unrbp3 + unrop3) / slpprdp;
        rdi4p = 60*(hrembp4 + hrop4 + hnrbp4 + hnrop4 +
            carbp4 + carop4 + canbp4 + canop4 +
            oarbp4 + oarop4 + oanbp4 +oanop4 +
            urbp4 + urop4 + unrbp4 + unrop4) / slpprdp;
      rdi5p = 60*(hrembp5 + hrop5 + hnrbp5 + hnrop5 +
            carbp5 + carop5 + canbp5 + canop5 +
            oarbp5 + oarop5 + oanbp5 +oanop5 +
            urbp5 + urop5 + unrbp5 + unrop5) / slpprdp;
    end;

  ************************************************************************************;
  * #10  RDI WITH AROUSALS
  * RDI with Arousals at specified desat
      [ (Total number of central apneas with arousal at specified desat)
      + (Total number of obstructive apneas with arousal at specified desat)
      + (hypopneas with arousal at specified desat)]
      / (hours of sleep)
  * For Profusion2 studies, include AASM hypopneas ('unsure events');
  ************************************************************************************;
    if slpprdp gt 0 then do;
      rdi0pa = 60*(hremba +hroa + hnrba + hnroa +
            carba + caroa + canba + canoa +
            oarba + oaroa + oanba + oanoa +
            urbpa + uropa + unrbpa + unropa) / slpprdp;
      rdi2pa = 60*(hremba2 +hroa2 + hnrba2 + hnroa2 +
            carba2 + caroa2 + canba2 + canoa2 +
            oarba2 + oaroa2 + oanba2 + oanoa2 +
            urbpa2 + uropa2 + unrbpa2 + unropa2) / slpprdp;
      rdi3pa = 60*(hremba3 +hroa3 + hnrba3 + hnroa3 +
            carba3 + caroa3 + canba3 + canoa3 +
            oarba3 + oaroa3 + oanba3 + oanoa3 +
            urbpa3 + uropa3 + unrbpa3 + unropa3) / slpprdp;
      rdi4pa = 60*(hremba4 +hroa4 + hnrba4 + hnroa4 +
            carba4 + caroa4 + canba4 + canoa4 +
            oarba4 + oaroa4 + oanba4 + oanoa4 +
            urbpa4 + uropa4 + unrbpa4 + unropa4) / slpprdp;
      rdi5pa = 60*(hremba5 +hroa5 + hnrba5 + hnroa5 +carba5+ caroa5 +
             canba5 + canoa5 +oarba5 +oaroa5 + oanba5 +oanoa5 +
             urbpa5 + uropa5 + unrbpa5 + unropa5) / slpprdp;
    end;

  ************************************************************************************;
  * #11 RDI BY BODY POSITION
  ************************************************************************************;

  ************************************************************************************;
  * #11a RDI IN SUPINE BODY POSITION
  * RDI at specified desat in supine body position
      [ (Total number of central apneas in supine body position at specified desat)
      + (Total number of obstructive apneas in supine body position at specified desat)
      + (hypopneas in supine body position at specified desat)]
      / (hours of sleep in supine body position)
  * exclude studies where there is no time in supine position
  ************************************************************************************;
    if supinep gt 0 then do;
      rdi0ps  = 60*(hrembp + hnrbp + carbp + canbp + oarbp + oanbp + urbp + unrbp)/(remepbp+nremepbp);
      rdi2ps  = 60*(hrembp2 + hnrbp2 + carbp2 + canbp2 + oarbp2 + oanbp2 + urbp2 + unrbp2)/(remepbp+nremepbp);
      rdi3ps  = 60*(hrembp3 + hnrbp3 + carbp3 + canbp3 + oarbp3 + oanbp3 + urbp3 + unrbp3)/(remepbp+nremepbp);
      rdi4ps  = 60*(hrembp4 + hnrbp4 + carbp4 + canbp4 + oarbp4 + oanbp4 + urbp4 + unrbp4)/(remepbp+nremepbp);
      rdi5ps  = 60*(hrembp5 + hnrbp5 + carbp5 + canbp5 + oarbp5 + oanbp5 + urbp5 + unrbp5)/(remepbp+nremepbp);
    end;

  ************************************************************************************;
  * #11b RDI IN NON-SUPINE BODY POSITION
  * RDI at specified desat in non-supine body position
      [ (Total number of central apneas in non-supine body position at specified desat)
      + (Total number of obstructive apneas in non-supine body position at specified desat)
      + (hypopneas in non-supine body position at specified desat)]
      / (hours of sleep in non-supine body position)
  * exclude studies where there is no time in non-supine position
  * For Profusion2 studies, include AASM hypopneas ('unsure events');
  ************************************************************************************;
    if nsupinep gt 0 then do;
      rdi0pns = 60*(hrop   + hnrop + carop + canop + oarop + oanop + urop + unrop)/(remepop+nremepop);
      rdi2pns = 60*(hrop2 +   hnrop2 + carop2 + canop2 + oarop2 + oanop2 + urop2 + unrop2)/(remepop+nremepop);
      rdi3pns = 60*(hrop3 +   hnrop3 + carop3 + canop3 + oarop3 + oanop3 + urop3 + unrop3)/(remepop+nremepop);
      rdi4pns = 60*(hrop4 +   hnrop4 + carop4 + canop4 + oarop4 + oanop4 + urop4 + unrop4)/(remepop+nremepop);
      rdi5pns = 60*(hrop5 +   hnrop5 + carop5 + canop5 + oarop5 + oanop5 + urop5 + unrop5)/(remepop+nremepop);
    end;

  ************************************************************************************;
  * #12 RDI IN REM AND NON-REM
  ************************************************************************************;

  ************************************************************************************;
  * #12a RDI IN REM SLEEP
  * RDI at specified desat in REM sleep
      [ (Total number of central apneas in REM sleep at specified desat)
      + (Total number of obstructive apneas in REM sleep at specified desat)
      + (hypopneas in REM sleep at specified desat)]
      / (hours of REM sleep)
  * For Profusion2 studies, include AASM hypopneas ('unsure events');
  ************************************************************************************;
    if minremp ne 0 then do;
      * REM;
      rdirem0p = 60*(hrembp + hrop + carbp + carop + oarbp +oarop + urbp + urop) / minremp;
      rdirem2p = 60*(hrembp2 + hrop2 + carbp2 + carop2 + oarbp2 + oarop2 + urbp2 + urop2) / minremp;
      rdirem3p = 60*(hrembp3 + hrop3 + carbp3 + carop3 + oarbp3 + oarop3 + urbp3 + urop3) / minremp;
      rdirem4p = 60*(hrembp4 + hrop4 + carbp4 + carop4 + oarbp4 + oarop4 + urbp4 + urop4) / minremp;
      rdirem5p = 60*(hrembp5 + hrop5 + carbp5 + carop5 + oarbp5 + oarop5 + urbp5 + urop5) / minremp;
    end;

  ************************************************************************************;
  * #12b RDI IN NON-REM SLEEP
  * RDI at specified desat in non-REM sleep
      [ (Total number of central apneas in non-REM sleep at specified desat)
      + (Total number of obstructive apneas in non-REM sleep at specified desat)
      + (hypopneas in non-REM sleep at specified desat)]
      / (hours of non-REM sleep)
  * exclude studies with no non-REM sleep;
  * For Profusion2 studies, include AASM hypopneas ('unsure events');
  ************************************************************************************;
    if minremp ne slpprdp then do;
      * NREM;
      rdinr0p  = 60*(hnrbp + hnrop + canbp + canop + oanbp +oanop + unrbp + unrop) / (slpprdp - minremp);
      rdinr2p  = 60*(hnrbp2 + hnrop2 + canbp2 + canop2 + oanbp2 + oanop2 + unrbp2 + unrop2) / (slpprdp - minremp);
      rdinr3p  = 60*(hnrbp3 + hnrop3 + canbp3 + canop3 + oanbp3 + oanop3 + unrbp3 + unrop3) / (slpprdp - minremp);
      rdinr4p  = 60*(hnrbp4 + hnrop4 + canbp4 + canop4 + oanbp4 + oanop4 + unrbp4 + unrop4) / (slpprdp - minremp);
      rdinr5p  = 60*(hnrbp5 + hnrop5 + canbp5 + canop5 + oanbp5 + oanop5 + unrbp5 + unrop5) / (slpprdp - minremp);
    end;

  ************************************************************************************;
  * #13 OAHI - all obstructive apneas and hypopneas with specified desat;
  * exclude studies where total sleep time is zero;
  ************************************************************************************;
    if slpprdp gt 0 then do;
      oahi4  = 60*(hrembp4 +hrop4 + hnrbp4 + hnrop4 + oarbp +oarop + oanbp +oanop ) / slpprdp;
      oahi3 = 60*(hrembp3 +hrop3 + hnrbp3 + hnrop3 + oarbp +oarop + oanbp +oanop ) / slpprdp;
    end;
    label oahi4 = 'Calculated - Obstructive apnea (all desats) Hypopnea (4% desat) Index'
      oahi3 = 'Calculated - Obstructive apnea (all desats) Hypopnea (3% desat) Index';

  ************************************************************************************;
  * #14 OBSTRUCTIVE APNEA INDEX
  * exclude studies with total sleep time = 0 or with poor airflow;
  * for OAI with arousals, exclude studies scored sleep/wake
  ************************************************************************************;
    if slpprdp gt 0 then do;
      oai0p  = 60*(oarbp +  oarop  + oanbp  + oanop) / slpprdp;
      oai4p  = 60*(oarbp4 + oarop4 + oanbp4 + oanop4) / slpprdp;
      oai4pa = 60*(oarba4 + oaroa4 + oanba4 + oanoa4) / slpprdp;
    end;

  ************************************************************************************;
  * #15 Central apnea index;
  * exclude studies with total sleep time = 0 or
  * for CAI with arousals, exclude studies scored sleep/wake
  ************************************************************************************;
    if slpprdp gt 0 then do;
      cai0p  = 60*(carbp +  carop  + canbp  + canop ) / slpprdp;
      cai4p  = 60*(carbp4 + carop4 + canbp4 + canop4 ) / slpprdp;
      cai4pa = 60*(carba4 + caroa4 + canba4 + canoa4 ) / slpprdp;
    end;

  ************************************************************************************;
  * #16 PERCENT TIME WITH SAO2 < 90,85,80,75
  ************************************************************************************;
      pctlt90 = pctsa90h;
      pctlt85 = pctsa85h;
      pctlt80 = pctsa80h;
      pctlt75 = pctsa75h;

  ************************************************************************************;
  * #17 AVERAGE SA02 IN REM, NREM
  * exclude studies scored as sleep/wake.
  ************************************************************************************;

      sao2rem = avsao2rh;
      sao2nrem = avsao2nh;

  ************************************************************************************;
  * #18 MINIMUM SA02 IN REM, NREM
  * exclude studies scored as sleep/wake.
  ************************************************************************************;
      if mnsao2rh ne 0 then losao2r = mnsao2rh;
        else losao2r = .;

      if mnsao2nh ne 0 then losao2nr = mnsao2nh;
        else losao2nr = .;

  ************************************************************************************;
  * #19 AVERAGE SA02 DURING SLEEP
  ************************************************************************************;
      *create holder variable for average saO2 in rem which = 0 if there is no rem
        (avoids avgsat being missing due to missing value in calculation);
      if avsao2rh = . then avsao2rh_holder = 0;
        else avsao2rh_holder = avsao2rh;

      avgsat = ((avsao2nh) * (tmstg1p+tmstg2p+tmstg34p) + (avsao2rh_holder)*(tmremp))/100;
      drop avsao2rh_holder;

  ************************************************************************************;
  * #19 MINIMUM SA02 DURING SLEEP
  ************************************************************************************;
      if losao2r = . then minsat = losao2nr;
      else if losao2nr = . then minsat = losao2r;
      else minsat = min(losao2r,losao2nr);

    * exclude studies scored as sleep/wake (minimum saturation in particular stages will not be valid);
      losao2r = .;
      losao2nr = .;

  ************************************************************************************;
  * #20 NUMBER OF PLM PER HOUR OF SLEEP
  ************************************************************************************;
    if slpprdp gt 0 then do;
      avgplm = 60*(plmslp/slpprdp);
    end;

  ************************************************************************************;
  * #20 JACKSON SPECIFIC INDEX CALCULATIONS
  ************************************************************************************;
    if slpprdp gt 0 then do;
      jhsahi0 = 60*(hrembp + hrop + hnrbp + hnrop +
            carbp + carop + canbp + canop +
            oarbp + oarop + oanbp + oanop +
            urbp + urop + unrbp + unrop) / slpprdp;
      jhsahi = 60*(hrembp3 + hrop3 + hnrbp3 + hnrop3 +
            carbp + carop + canbp + canop +
            oarbp + oarop + oanbp + oanop +
            urbp3 + urop3 + unrbp3 + unrop3) / slpprdp;
      jhsahi_4psubtle = 60*(hrembp4 + hrop4 + hnrbp4 + hnrop4 +
            carbp + carop + canbp + canop +
            oarbp + oarop + oanbp + oanop +
            urbp3 + urop3 + unrbp3 + unrop3) / slpprdp;
      uni0p = 60*(urbp + urop + unrbp + unrop) / slpprdp;
      uni3p = 60*(urbp3 + urop3 + unrbp3 + unrop3) / slpprdp;
      hyi0p = 60*(hrembp + hrop + hnrbp + hnrop) / slpprdp;
      hyi3p = 60*(hrembp3 + hrop3 + hnrbp3 + hnrop3) / slpprdp;
      hyi4p = 60*(hrembp4 + hrop4 + hnrbp4 + hnrop4) / slpprdp;
      aasm3p = 60*(urbp3 + urop3 + unrbp3 + unrop3) / slpprdp;
    end;

  end;
  run;




***************************************************************************************;
* Check data
***************************************************************************************;
  * run macro to create and print title for data checking;
  %datechecktitle(jhspsg,JHS PSG Dataset);

  proc sql;
    title "JHS PSG: Has scored report (.txt), but no matching QS";
    select pptid, stdydt, scorerid from jhspsg
    where hastxt = 1 and hasqs ne 1; title;
  quit;

  proc sql;
    title "JHS PSG: Has QS form, but no matching scored report (.txt)";
    select pptid, stdydt, scorerid from jhspsg
    where hastxt ne 1 and hasqs = 1 and psgqs_overall ne 2; title;
  quit;

  proc sql;
    title "JHS PSG: Missing heart rate variable(s) - likely N/A in SAS report";
    select pptid, stdydt, BPMAVG, BPMMIN, BPMMAX, scorerid
    from jhspsg
    where hastxt = 1 and (bpmavg < 0 or bpmmin < 0 or bpmmax < 0); title;
  quit;

  proc sql;
    title "JHS PSG: Low Average Sat (<80) - possible artifact";
    select pptid, psgqs_overall, psgqs_oximetry_quality, avgsat, scorerid
    from jhspsg
    where hastxt = 1 and avgsat < 80;
  quit;

  proc sql;
    title "JHS PSG: Low Minimum Sat (<70) - possible artifact";
    select pptid, psgqs_overall, psgqs_oximetry_quality, minsat, scorerid
    from jhspsg
    where hastxt = 1 and minsat < 70 and
      pptid not in ('J558661','J580492','J347747');
        /* confirmed by scorer as real minimums < 70 */
  quit;


***************************************************************************************;
* Compare to previous dataset
***************************************************************************************;
  title "Compare to Previous PSG Dataset";
  proc compare base=jhs.jhspsg compare=jhspsg transpose nomissbase nosummary;
    id pptid stdydt;
  run;
  title;


*****************************************************************************************;
* Create permanent datasets
*****************************************************************************************;
  data jhs.jhspsg jhs2.jhspsg_&sasfiledate;
    set jhspsg;
    if pptid ne ""; /* only keep records with valid participant ids */
  run;

