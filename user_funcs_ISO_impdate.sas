/****************************************************************************************
Program:          user_funcs_ISO_impdate.sas
SAS Version:      SAS 9.4m7
Developer:        Richann Watson 
Date:             2024-03-16 
Operating Sys:    Windows 11
----------------------------------------------------------------------------------------- 

Revision History:
Date: 
Requestor: 
Modification: 
Modifier: 
-----------------------------------------------------------------------------------------

NOTE: This is retrieved from https://github.com/rwatson724/Programming-Code-From-Papers/users_funcs_ISO_impdate.sas
****************************************************************************************/
libname fcmp 'C:\Users\gonza\OneDrive - datarichconsulting.com\Desktop\Conferences\Impute Dates';

proc fcmp outlib = fcmp.funcs.ISO_impdate;
   function isoimpdt(dattim $, refdt, imputfl $, imptyp $); 
      outargs imputfl;

      length impdt 8 ___dt $10 __dtyr __dtmo __dtdy __impmo __impdy __impmos __impdys __impmoe __impdye __impmom __impdym 8 
             imputfl __start __end __mid $1 __tempvar $2;
      format impdt refdt date9.;

      /* extract the date portion only */
      ___dt = strip(scan(dattim, 1, 'T'));

      /* if year is missing then impute the entire date */
      if ___dt =: '-' then call missing(of __dt:);
      else if anydigit(first(___dt)) then do;
         __dtyr = input(substr(___dt, 1, 4), best.);
         if substr(___dt, 6, 1) = '-' then call missing(__dtmo, __dtdy);
         else if anydigit(substr(___dt, 6, 1)) then do;
            __dtmo = input(substr(___dt, 6, 2), best.);
            if anydigit(substr(___dt, 9, 1)) then __dtdy = input(substr(___dt, 9, 2), best.);
            else call missing(__dtdy);
         end;
      end;

      /* determine the imputation month and imputation day number */
      /* it is assumed that the argument applies to both month and day */
      /* if need different values then need an additional argument     */
      if prxmatch('/S|F|B/i', imptyp) then do;
         __start = 1;
         __impmos = 1;
         __impdys = 1;
      end;
      if prxmatch('/L|E/i', imptyp) then do;
         __end = 1;
         __impmoe = 12;
         if not missing(__dtmo) and __dtmo ne 12 then __impdye = day(mdy(__dtmo + 1, 1, __dtyr) - 1);
         else if missing(__dtmo) or __dtmo = 12 then __impdye = 31;
      end;
      if prxmatch('/M|H/i', imptyp) then do;
         __mid = 1;
         __impmom = 6;
         __impdym = 15;
      end;
      __impmo = coalesce(__impmos, __impmoe, __impmom);
      __impdy = coalesce(__impdys, __impdye, __impdym);
      
      /* impute dates based on the following rules: denoted in IMPTYP argument */
      if not missing(__dtyr) then do;
         if nmiss(__dtmo, __dtdy) = 0 then impdt = mdy(__dtmo, __dtdy, __dtyr);
         else if missing(__dtmo) then do;
            imputfl = 'M';
            if prxmatch('/R|Y/i', imptyp) and __dtyr = year(refdt) then impdt = refdt;
            else if __dtyr < year(refdt) and __end = 1 then impdt = mdy(__impmoe, __impdye, __dtyr);
            else if __dtyr < year(refdt) and __mid = 1 then impdt = mdy(__impmom, __impdym, __dtyr);
            else impdt = mdy(__impmo, __impdy, __dtyr);
         end;
         else if missing(__dtdy) then do;
             imputfl = 'D';
            if prxmatch('/R|Y/i', imptyp) and __dtyr = year(refdt) and __dtmo = month(refdt) then impdt = refdt;
            else if mdy(1, __dtmo, __dtyr) < mdy(1, month(refdt), year(refdt)) and __end = 1 then impdt = mdy(__dtmo, __impdye, __dtyr);
            else if mdy(1, __dtmo, __dtyr) < mdy(1, month(refdt), year(refdt)) and __mid = 1 then impdt = mdy(__dtmo, __impdym, __dtyr);
            else impdt = mdy(__dtmo, __impdy, __dtyr);
         end;
      end;
      else if missing(__dtyr) then do;
         if find(imptyp, 'Y', 'i') then do;
            impdt = refdt;
            imputfl = 'Y';
         end;
         else call missing(impdt, imputfl);
      end;

      return(impdt);
   endfunc;
quit;