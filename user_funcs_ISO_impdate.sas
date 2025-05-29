/****************************************************************************************
Program:          user_funcs_ISO_impdate.sas
SAS Version:      SAS 9.4m8
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
----------------------------------------------------------------------------------------- 
****************************************************************************************/
libname fcmp 'C:\Desktop\GitHub\Programming-Code-From-Papers';

proc fcmp outlib = fcmp.funcs.ISO_impdate;
   function isoimpdt(dattim $, refdt, imputfl $, imptyp $, impnum $, useref $); 
      outargs imputfl;

      length impdt 8 ___dt $10 __dtyr __dtmo __dtdy __impmo __impdy 8 imputfl $1 __tempvar $2;
      format impdt date9.;

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
      if upcase(impnum) in ('S' 'F' 'B' '1') then do;
         __impmo = 1;
         __impdy = 1;
      end;
      else if upcase(impnum) in ('L' 'E' '31' '30') then do;
         __impmo = 12;
         if not missing(__dtmo) and __dtmo ne 12 then __impdy = day(mdy(__dtmo + 1, 1, __dtyr) - 1);
         else if missing(__dtmo) or __dtmo = 12 then __impdy = 31;
      end;
      else if upcase(impnum) in ('M' 'H' '6' '15') then do;
         __impmo = 6;
         __impdy = 15;
      end;

      /* impute dates based on the following rules:                                                      */
      /* missing year - for start date then impute to the reference date                                 */
      /*                for end date no imputation is to be done                                         */
      /* missing month - for start date if year same as reference date then impute to reference date     */
      /*                 for start date if year not same as ref date then impute to 1st mon using impmn  */
      /*                 for end date impute to end of year regardless of year                           */
      /* missing day - for start date if year and month same as ref date then impute to ref date         */
      /*               for start date if year and month not same as ref date then impute day using impdy */
      /*               for end date impute to the end of the month regardless of year and month          */
      if not missing(__dtyr) then do;
         if nmiss(__dtmo, __dtdy) = 0 then impdt = mdy(__dtmo, __dtdy, __dtyr);
         else if missing(__dtmo) then do;
            imputfl = 'M';
            if upcase(first(useref)) = 'Y' and upcase(imptyp) = 'ST' and __dtyr = year(refdt) then impdt = refdt;
            else impdt = mdy(__impmo, __impdy, __dtyr);
         end;
         else if missing(__dtdy) then do;
             imputfl = 'D';
            if upcase(first(useref)) = 'Y' and upcase(imptyp) = 'ST' and __dtyr = year(refdt) and __dtmo = month(refdt) then impdt = refdt;
            else impdt = mdy(__dtmo, __impdy, __dtyr);
         end;
      end;
      else if missing(__dtyr) then do;
         if upcase(first(useref)) = 'Y' and upcase(imptyp) = 'ST' then do;
            impdt = refdt;
            imputfl = 'Y';
         end;
         else call missing(impdt, imputfl);
      end;

      return(impdt);
   endfunc;
quit;