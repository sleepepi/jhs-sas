****************************************************************************************;
* Set options
****************************************************************************************;
options source nodate nonumber nofmterr formdlim = ' ' fmtsearch = (jhs) nomprint noxwait;

***************************************************************************************;
* Set JHS libraries
***************************************************************************************;
%let jhspath = \\rfa01\bwh-sleepepi-jhs\data;
libname jhs "&jhspath.\SAS\_datasets";
libname jhs2 "&jhspath.\SAS\_archive";

***************************************************************************************;
* Store current date
***************************************************************************************;
data _null_;
  call symput("datetoday",put("&sysdate"d,mmddyy8.));
  call symput("date6",put("&sysdate"d,mmddyy6.));
  call symput("date10",put("&sysdate"d,mmddyy10.));
  call symput("filedate",put("&sysdate"d,yymmdd10.));
  call symput("sasfiledate",put(year("&sysdate"d),4.)||put(month("&sysdate"d),z2.)||put(day("&sysdate"d),z2.));
run;

***************************************************************************************;
* Include commonly used macros
***************************************************************************************;
%include "\\rfa01\BWH-SleepEpi\procedures\sas\macros\load dce macros.sas";
