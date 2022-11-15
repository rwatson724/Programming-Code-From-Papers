/****************************************************************************************
Program:          user_funcs_ISO_DATE.sas
SAS Version:      SAS 9.4m7
Developer:        Richann Watson 
Date:             2022-04-23 
Operating Sys:    Windows 10
----------------------------------------------------------------------------------------- 

Revision History:
Date: 
Requestor: 
Modification: 
Modifier: 
----------------------------------------------------------------------------------------- 
****************************************************************************************/
libname fcmp 'C:\Users\gonza\Desktop\GitHub\SAS-Papers\FCMP';

proc fcmp outlib = fcmp.funcs.ISO_date;
   /* need to zero fill each non-missing month, day, hour, minute, second */
   subroutine zfill(_comp $);
      outargs _comp;
      if not missing(_comp) and not( notdigit(cats(_comp)) )  then _comp  = put(input(_comp, best.), Z2.);
      else _comp = '-';
   endsub;

   /* input values are character so need $ for each */
   subroutine dttmfmt(_year $, _month $, _day $, _hour $, _minute $, _second $);
      outargs _year, _month, _day, _hour, _minute, _second;
      /* make sure year is a four-digit number */
      if not( notdigit(cats(_year)) ) then do;
         if length(strip(_year)) = 4 then _year = strip(_year);
         else if length(strip(_year)) = 2 then do;
           if input(_year, best.) <= 40 then _year = cats('20', _year);
           else _year = cats('19', _year);
         end;
      end;
      else _year = '-';

      /* need to zero fill each non-missing month, day, hour, minute, second */
      call zfill(_month);
      call zfill(_day);
      call zfill(_hour);
      call zfill(_minute);
      call zfill(_second);
   endsub;

   function ISO_DTTM(dattim $) $; /* all inputs are character so need $ after input argument */
      /* for all character variables in the function, need to specify the length */
      length __dtc __dttm $20 iso_dtc $10 iso_tmc $8 year $4 month $2 day $2;

      /* extract the date portion and compress any dashes to see what the format is */
      __dtpart = compress(scan(dattim, 1, ' T:', 'm'), '-');

      /* depending on the length will determine if it is date9 (9 characters), yymmdd8 (8 characters), or yymmdd10. (10 characters) */
      /* need to convert all dates to the yymmdd10 format so that further processing can proceed - if not then need to get out      */
      if length(strip(__dtpart)) in (7 9) then do;
         year = strip(substr(__dtpart, 6 /*, 4*/));
         if strip(substr(__dtpart, 3, 3)) in ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC') then 
               month = put(whichc(strip(substr(__dtpart, 3, 3)), 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'), Z2.);
         else month = substr(__dtpart, 3, 2);
         day = strip(substr(__dtpart, 1, 2));
      end;
      else if length(strip(__dtpart)) = 8 then do;
         year = strip(substr(__dtpart, 1, 4));
         month = strip(substr(__dtpart, 5, 2));
         day = strip(substr(__dtpart, 7, 2));
      end;
      else if lengthn(strip(__dtpart)) = 0 then call missing(year, month, day);
      else do;
         if length(strip(__dtpart)) = 4 then
           put %sysfunc(compress("WARN ING:")) dattim "insufficient to determine if date part represents YYYY or DDMM or MMDD.";
         else if length(strip(__dtpart)) in (5 6) then 
           put %sysfunc(compress("WARN ING:")) dattim "insufficient to determine if date part represents DDMMM or YYYYM or YYMMDD or YYYYMM or MMDDYY.";
         else
           put %sysfunc(compress("WARN ING:")) dattim "date part not in a usable format.";
         __dtc = '_ERROR_';
         return(__dtc);
      end;

      /* extract the time portion to see what the format is */
      /* extract time portion to see if hh:mm:ss (assume 24-hr clock) or if HH:MM:SS AM/PM (12-hr clock) */
      __tmpart = substr(dattim, prxmatch('/T|:| /i', dattim) );
      if first(__tmpart) in ('T' ':') then __tmpart = substr(__tmpart, 2);
      
      if prxmatch('/AM|PM/i', __tmpart) then __tmpart2 = transtrn(transtrn(__tmpart, 'AM', trimn('')), 'PM', trimn(''));
      else __tmpart2 = __tmpart;

      /* split the time components */
      array tm_c (3) $ hour minute second;
      do i = 1 to 3;
         tm_c[i] = scan(strip(__tmpart2), i, 'T:', 'm');
         if strip(tm_c[i]) in ('' '.') then tm_c[i] = '-';

      end;
      
      if find(__tmpart, 'PM') and strip(hour) ne '12' and not(notdigit(strip(hour))) then hour = put(input(hour, best.) + 12, Z2.);
      else if find(__tmpart, 'AM') and strip(hour) = '12' then hour = '00';

      call dttmfmt(year, month, day, hour, minute, second);

      /* use new variables to build ISO 8601 dates in the proper format */
      iso_dtc = catx('-', year, month, day);
      iso_tmc = catx(':', hour, minute, second);

      /* if time is nothing but '-' and ':' then default to blank */
      /* if there is at least one number portion then need to keep*/
      /* up through the last time element that has a numeric part */
      if notpunct(strip(iso_tmc)) > 0 then _iso_tmc = substr(iso_tmc, 1, notpunct(strip(iso_tmc), -length(iso_tmc)));
      else call missing(_iso_tmc);

      /* combine time with date to build ISO datetime */
      __dttm = catx('T', iso_dtc, _iso_tmc);

      /* if there is no time portion then keep only up to last numeric portion of date */
      if anyalpha(strip(__dttm)) > 0 then __dtc = __dttm;
      else if notpunct(strip(__dttm)) > 0 then __dtc = substr(__dttm, 1, notpunct(strip(__dttm), -length(__dttm)));
      else call missing(__dtc);

      return(__dtc);
   endfunc;
quit;