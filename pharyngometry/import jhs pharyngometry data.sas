****************************************************************************************;
* Establish JHS libraries and options
****************************************************************************************;
%include "\\rfa01\bwh-sleepepi-jhs\data\sas\jhs options and libnames.sas";


***************************************************************************************;
* Read in curve scores from Slice export
***************************************************************************************;
  data slice_inphar1;
    set jhs.jhsslice_grids;

    *only keep certain sheets;
    if name = "Pharyngometry QS";

    keep subject pharynqs_breathnum--pharynqs_mbrs;
  run;

  data slice_inphar2;
    set jhs.jhsslice;

    *only keep certain sheets;
    if name = "Pharyngometry QS";

    keep subject pharynqs_recording_date--pharynqs_nbqs;
  run;

  proc sort data=slice_inphar1;
    by subject;
  run;

  proc sort data=slice_inphar2;
    by subject;
  run;

  data slice_inphar;
    merge slice_inphar1 slice_inphar2;
    by subject;
  run;

  data slice_phar;
    merge slice_inphar (in=mb1 keep=subject--pharynqs_nbqs where=(pharynqs_breathnum=1) rename=(pharynqs_mbqs=curveqs2 pharynqs_mbrs=curvers2 pharynqs_nbqs=curveqs1))
        slice_inphar (in=mb2 keep=subject--pharynqs_nbqs where=(pharynqs_breathnum=2) rename=(pharynqs_mbqs=curveqs3 pharynqs_mbrs=curvers3 pharynqs_nbqs=curveqs1))
        slice_inphar (in=mb3 keep=subject--pharynqs_nbqs where=(pharynqs_breathnum=3) rename=(pharynqs_mbqs=curveqs4 pharynqs_mbrs=curvers4 pharynqs_nbqs=curveqs1));
    by subject;
    drop pharynqs_breathnum;
  run;

  data segments;
    length pptid 6. pharynqs_recording_date pharynqs_date_scored 8. curveqs1 curveqs2 curvers2 curveqs3 curvers3 curveqs4 curvers4 3.;
    set slice_phar;

    pptid = input(substr(subject,2,6),6.);
    drop subject;
  run;

  proc sort data=segments;
    by pptid;
  run;


***************************************************************************************;
* Read in scored data files
***************************************************************************************;
  filename newdata pipe 'dir "\\rfa01\bwh-sleepepi\projects\src\jhs\Data\Pharyngometry\Scored\J*.*" /b';

  data pharynscored_in;
    infile newdata truncover;
    input f2r $24.;
    fil2read="&jhspath.\Pharyngometry\Scored\"||f2r;
    infile dummy filevar=fil2read end=done truncover lrecl=256;
    do while(not done);
      input pdata $256.;
      output;
     end;
  run;


***************************************************************************************;
* Extract header information from each data file (pharynheader);
***************************************************************************************;
  data pharynheader;
    length pptid 6. pharyn_testdate 8. ptname $16. pharyn_dob segmin1 segmax1
        segmin2 segmax2 segmin3 segmax3 segmin4 segmax4 8.;
    set pharynscored_in;
    by f2r;
    retain pharyn_testdate ptname pharyn_dob segmin1 segmax1
        segmin2 segmax2 segmin3 segmax3 segmin4 segmax4;
    if first.f2r then do;
      pharyn_testdate=.;
      ptname    = '';
      pharyn_dob  = .;
      segmin1   = .;
      segmax1   = .;
      segmin2   = .;
      segmax2   = .;
      segmin3   = .;
      segmax3   = .;
      segmin4   = .;
      segmax4   = .;
    end;

    if index(pdata,'Date of Test')>0 then do;
      pharyn_testdate_c = trim(left(substr(pdata,16,10)));
      if length(pharyn_testdate_c) = 8 then
          pharyn_testdate = input(pharyn_testdate_c,mmddyy8.);
      else if length(pharyn_testdate_c) = 10 then
          pharyn_testdate = input(pharyn_testdate_c,mmddyy10.);
    end;
    if index(pdata,'Patient Name')>0 then ptname = substr(pdata,16,16);
    if index(pdata,'Date of Birth')>0 then do;
      pharyn_dob_c = trim(left(substr(pdata,17,10)));
      if length(pharyn_dob_c) = 8 then
        pharyn_dob = input(pharyn_dob_c,mmddyy8.);
      else if length(pharyn_dob_c) = 10 then
        pharyn_dob = input(pharyn_dob_c,mmddyy10.);
    end;
    if index(pdata,'Mark 1 2')>0 then segmin1 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 1 3')>0 then segmax1 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 2 2')>0 then segmin2 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 2 3')>0 then segmax2 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 3 2')>0 then segmin3 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 3 3')>0 then segmax3 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 4 2')>0 then segmin4 = input(substr(pdata,12,8),8.);
    if index(pdata,'Mark 4 3')>0 then segmax4 = input(substr(pdata,12,8),8.);
    format pharyn_testdate pharyn_dob mmddyy8.;

    format pharyn_testdate pharyn_dob mmddyy8.;
    f2r=upcase(f2r);
    personidc = substr(f2r,1,7);
    pptid = input(substr(f2r,2,6),6.);

    file_id = input(substr(ptname,4,4),4.);

    drop pharyn_testdate_c pharyn_dob_c pdata ;
    if last.f2r then output;

  run;

  proc sort data=pharynheader;
    by pptid;
  run;


***************************************************************************************;
* Extract curve data from each data file (pharyndata);
***************************************************************************************;
  * set raw data and create separate variables for each datapoint;
  data pharyndata;
    retain pptid;
    set Pharynscored_in;
    if substr(pdata,1,1) = '"' then delete;
    else do;
      dist1 = input(scanq(pdata,1," "),6.2);
      csa1  = input(scanq(pdata,2," "),6.2);
      sd1   = input(scanq(pdata,3," "),6.2);
      dist2 = input(scanq(pdata,4," "),6.2);
      csa2  = input(scanq(pdata,5," "),6.2);
      sd2   = input(scanq(pdata,6," "),6.2);
      dist3 = input(scanq(pdata,7," "),6.2);
      csa3  = input(scanq(pdata,8," "),6.2);
      sd3   = input(scanq(pdata,9," "),6.2);
      dist4 = input(scanq(pdata,10," "),6.2);
      csa4  = input(scanq(pdata,11," "),6.2);
      sd4   = input(scanq(pdata,12," "),6.2);
    end;
    drop pdata;
    f2r=upcase(f2r);
    * create id;
    pptid = input(substr(f2r,2,6),6.);


    * remove header information records;
    if dist1 = . then delete;
  run;

  proc sort data=pharyndata;
    by pptid;
  run;


***************************************************************************************;
* CALCULATE SUMMARY VARIABLES FOR EACH CURVE
***************************************************************************************;
  * limit to values within analysis segment (based on segmin and segmax);
  * calculate mean cross-sectional area in segment (excluding last measurement);
  * calculate min and max cross-sectional area in segment (including last measurement);
  * get cross-sectional area at beginning and end points of segment;
  * get lengths at which min and max cross-sectional area occur;
  * calculate length of analysis segment;
  * calculate relative distance of max cross-sectional area;
  * calculate segment volume;
  %macro runcsa;
    %do c=1 %to 4;
      * create separate datasets for each curve, merged with segment length info;
      data p_&c (keep=pptid segmin&c segmax&c dist&c csa&c sd&c);
        merge pharynheader pharyndata;
        by pptid;
      run;

    * keep only the desired segment based on segment lenghts;
      data p_&c;
        set p_&c;
        if dist&c < segmin&c or dist&c > segmax&c then delete;
      run;

      * get mean cross-sectional area in segment per id (exclude last segment);
      proc means data=p_&c noprint;
        var csa&c;
        class pptid;
        output out=means&c;
        * exclude last segment from mean;
        where dist&c ne segmax&c;
      run;

      proc sort data=means&c;
        by pptid;
      run;

      * transpose means output to one line per id;
      data means&c (keep=pptid meancsa&c);
        set means&c;
        by pptid;
        if pptid ne .;
        retain meancsa&c;
        if first.pptid then do;
          meancsa&c = .;
        end;
        if _stat_ = "MEAN" then meancsa&c = csa&c;
        if last.pptid then output;
      run;

      * get min and max cross-sectional area in segment per id;
      proc means data=p_&c noprint;
        var csa&c;
        class pptid;
        output out=means2&c;
      run;

      proc sort data=means2&c;
        by pptid;
      run;

      * transpose means output to one line per id;
      data means2&c (keep=pptid mincsa&c maxcsa&c);
        set means2&c;
        by pptid;
        if pptid ne .;
        retain mincsa&c maxcsa&c;
        if first.pptid then do;
          mincsa&c = .;
          maxcsa&c = .;
        end;
        if _stat_ = "MIN" then mincsa&c = csa&c;
        if _stat_ = "MAX" then maxcsa&c = csa&c;
        if last.pptid then output;
      run;

      * merge data with means dataset;
      data p_&c;
        merge p_&c means&c means2&c;
        by pptid;
      run;

      * get csa at beginning and end of segment, and get lengths of min and max csa;
      data p_&c (drop=dist&c--sd&c);
        set p_&c;
        by pptid;
        retain proxcsa&c distcsa&c mincsadist&c maxcsadist&c;
        if first.pptid then do;
          proxcsa&c =.;
          distcsa&c =.;
          mincsadist&c =.;
          maxcsadist&c =.;
        end;
        if dist&c = segmin&c then proxcsa&c = csa&c;
        if dist&c = segmax&c then distcsa&c = csa&c;
        if csa&c = mincsa&c then mincsadist&c = dist&c;
        if csa&c = maxcsa&c then maxcsadist&c = dist&c;
        if last.pptid then output;
      run;

      * create summary variables for segment length and relative distance of max csa;
      data p_&c;
        retain pptid segmin&c segmax&c seglength&c proxcsa&c distcsa&c mincsa&c mincsadist&c maxcsa&c maxcsadist&c maxcsareldist&c meancsa&c;
        set p_&c;
        seglength&c = segmax&c - segmin&c;
        maxcsareldist&c = (maxcsadist&c - segmin&c) / seglength&c;
        vol&c = meancsa&c * seglength&c;
      run;

      proc datasets library=work nolist;
        delete means&c means2&c;
      quit;

      data p_&c;
        retain pptid;
        set p_&c;
      run;
    %end;
  %mend;

  %runcsa;


***************************************************************************************;
* Merge scored data with curve ratings
***************************************************************************************;
  * generate individual datasets to process each curve separately;
  data pharynvol pharyncheck;
    merge segments
        pharynheader (in=b)
        p_1 p_2 p_3 p_4;
    by pptid;
    if b;

    * create flag for if at least one curve passed;
    if curveqs2 = 1 or curveqs3 = 1 or curveqs4 = 1 then onepass = 1;

    *******************************************************************************;
    * create summary variables;
    * Min and mean cross sectional area averaged over 3 mouth breaths for those graphs which passed;
    %macro recodevars(var,label);
      * create holder variables used in calculations;
      * cycle through each of the curves (1-4);
      %do i=1 %to 4;
        * create holder variable that will be the value if the curve passed;
        if curveqs&i = 1 then p&var.&i = &var.&i;
        else p&var.&i = .;
        * create holder variable that will be the value if the curve is passed or equivocal;
        if curveqs&i in (1,3) then e&var.&i = &var.&i;
        else e&var.&i = .;
      %end;

      * calculate means for each curve based on curve scores;
      * "pass" variable is the mean of passed curves;
      &var.pass = mean(p&var.2,p&var.3,p&var.4);
      * "psss or equivocal" variable is the mean of passed or equivocal curves;
      &var.passeq = mean(e&var.2,e&var.3,e&var.4);
      * "pass or equivocal with at least one passed" variable is the mean of
        passed or equivocal curves where at least one passed;
      if onepass = 1 then &var.passeq1p = &var.passeq;


      label &var.pass = "Pharyn: Mean &label for passed curves"
        &var.passeq = "Pharyn: Mean &label for passed or equivocal curves"
        &var.passeq1p = "Pharyn: Mean &label for passed or equivocal curves (with at least one passed)"
        ;

      format &var.pass &var.passeq &var.passeq1p 8.2;
      drop p&var.1 p&var.2 p&var.3 p&var.4 e&var.1 e&var.2 e&var.3 e&var.4;
    %mend;

    %recodevars(meancsa,cross-sectional area (cm2));
    %recodevars(mincsa,minimum cross-sectional area (cm2));
    %recodevars(maxcsa,maximum cross-sectional area (cm2));
    %recodevars(maxcsareldist,relative location of maximum csa (%));
    %recodevars(vol,volume (cc));
    %recodevars(seglength,segment length (cm));
    %recodevars(proxcsa,proximal cross-sectional area (cm2));
    %recodevars(distcsa,distal cross-sectional area (cm2));


    drop onepass;

    * Calculate percent difference between min and max mouth breath volumes;
    * Don't use vol1 because it is actually a nose breath;
    volmin = min (vol2, vol3, vol4);
    volmax = max (vol2, vol3, vol4);
    vol_percent_diff = ((volmax - volmin)/(volmax + volmin)/2)*100;


    * assign labels;
    label
      pptid = 'Pharyn: Patient ID number'
      pharynqs_recording_date = 'Pharyn: Date of test'
      pharynqs_date_scored = 'Pharyn: Date test scored'
      curveqs1 = 'Pharyn: Nose breath quality score'
      curveqs2 = 'Pharyn: Mouth breath 1 quality score'
      curvers2 = 'Pharyn: Mouth breath 1 reproducibility score'
      curveqs3 = 'Pharyn: Mouth breath 2 quality score'
      curvers3 = 'Pharyn: Mouth breath 2 reproducibility score'
      curveqs4 = 'Pharyn: Mouth breath 3 quality score'
      curvers4 = 'Pharyn: Mouth breath 3 reproducibility score'
      ptname = 'Pharyn: pptid'
      segmin1 = 'Pharyn: Distance to beginning of analysis segment (cm) (Nose breath)'
      segmax1 = 'Pharyn: Distance to end of analysis segment (cm) (Nose breath)'
      segmin2 = 'Pharyn: Distance to beginning of analysis segment (cm) (Curve 1)'
      segmax2 = 'Pharyn: Distance to end of analysis segment (cm) (Curve 1)'
      segmin3 = 'Pharyn: Distance to beginning of analysis segment (cm) (Curve 2)'
      segmax3 = 'Pharyn: Distance to end of analysis segment (cm) (Curve 2)'
      segmin4 = 'Pharyn: Distance to beginning of analysis segment (cm) (Curve 3)'
      segmax4 = 'Pharyn: Distance to end of analysis segment (cm) (Curve 3)'
      seglength1 = 'Pharyn: Segment Length (cm) (Nose breath)'
      proxcsa1 = 'Pharyn: Proximal cross-sectional area (cm2) (Nose breath)'
      distcsa1 = 'Pharyn: Distal cross-sectional area (cm2) (Nose breath)'
      mincsa1 = 'Pharyn: Minimum cross-sectional area (cm2) (Nose breath)'
      mincsadist1 = 'Pharyn: Distance of minimum cross-sectional area (cm) (Nose breath)'
      maxcsa1 = 'Pharyn: Maximum cross-sectional area (cm2) (Nose breath)'
      maxcsadist1 = 'Pharyn: Distance of maximum cross-sectional area (cm) (Nose breath)'
      maxcsareldist1 = 'Pharyn: Relative distance of maximum cross-sectional area (%) (Nose breath)'
      meancsa1 = 'Pharyn: Mean cross-sectional area (cm2) (Nose breath)'
      seglength2 = 'Pharyn: Segment Length (cm) (Curve 1)'
      proxcsa2 = 'Pharyn: Proximal cross-sectional area (cm2) (Curve 1)'
      distcsa2 = 'Pharyn: Distal cross-sectional area (cm2) (Curve 1)'
      mincsa2 = 'Pharyn: Minimum cross-sectional area (cm2) (Curve 1)'
      mincsadist2 = 'Pharyn: Distance of minimum cross-sectional area (cm) (Curve 1)'
      maxcsa2 = 'Pharyn: Maximum cross-sectional area (cm2) (Curve 1)'
      maxcsadist2 = 'Pharyn: Distance of maximum cross-sectional area (cm) (Curve 1)'
      maxcsareldist2 = 'Pharyn: Relative distance of maximum cross-sectional area (%) (Curve 1)'
      meancsa2 = 'Pharyn: Mean cross-sectional area (cm2) (Curve 1)'
      seglength3 = 'Pharyn: Segment Length (cm) (Curve 2)'
      proxcsa3 = 'Pharyn: Proximal cross-sectional area (cm2) (Curve 2)'
      distcsa3 = 'Pharyn: Distal cross-sectional area (cm2) (Curve 2)'
      mincsa3 = 'Pharyn: Minimum cross-sectional area (cm2) (Curve 2)'
      mincsadist3 = 'Pharyn: Distance of minimum cross-sectional area (cm) (Curve 2)'
      maxcsa3 = 'Pharyn: Maximum cross-sectional area (cm2) (Curve 2)'
      maxcsadist3 = 'Pharyn: Distance of maximum cross-sectional area (cm) (Curve 2)'
      maxcsareldist3 = 'Pharyn: Relative distance of maximum cross-sectional area (%) (Curve 2)'
      meancsa3 = 'Pharyn: Mean cross-sectional area (cm2) (Curve 2)'
      seglength4 = 'Pharyn: Segment Length (cm) (Curve 3)'
      proxcsa4 = 'Pharyn: Proximal cross-sectional area (cm2) (Curve 3)'
      distcsa4 = 'Pharyn: Distal cross-sectional area (cm2) (Curve 3)'
      mincsa4 = 'Pharyn: Minimum cross-sectional area (cm2) (Curve 3)'
      mincsadist4 = 'Pharyn: Distance of minimum cross-sectional area (cm) (Curve 3)'
      maxcsa4 = 'Pharyn: Maximum cross-sectional area (cm2) (Curve 3)'
      maxcsadist4 = 'Pharyn: Distance of maximum cross-sectional area (cm) (Curve 3)'
      maxcsareldist4 = 'Pharyn: Relative distance of maximum cross-sectional area (%) (Curve 3)'
      meancsa4 = 'Pharyn: Mean cross-sectional area (cm2) (Curve 3)'
      vol1  = 'Pharyn: Volume (cc) (Nose breath)'
      vol2  = 'Pharyn: Volume (cc) (curve 1)'
      vol3  = 'Pharyn: Volume (cc) (curve 2)'
      vol4  = 'Pharyn: Volume (cc) (curve 3)'
      ;

    if pptid then output pharynvol;
    else output pharyncheck;
    drop pharyn_testdate pharyn_dob;
  run;

  proc sort data=pharynvol;
    by pptid;
  run;


***************************************************************************************;
* Drop variables used only for data checking
***************************************************************************************;
  data jhspharyn;
    set pharynvol;
    drop pharyn_testdate pharyn_dob personidc file_id volmin volmax vol_percent_diff;
    rename f2r = pharyn_filename;
  run;


***************************************************************************************;
* Create permanent SAS dataset
***************************************************************************************;
  data jhs.jhspharyn jhs2.jhspharyn_&sasfiledate;
    set jhspharyn;
    if pptid ne "";
  run;
