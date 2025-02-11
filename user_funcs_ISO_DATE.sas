/****************************************************************************************
Program:          FN_ISODTTM.sas
SAS Version:      SAS 9.4m7
Developer:        Richann Watson 
Date:             2022-04-23 
Operating Sys:    Windows 10
Purppose:         User-defined function that will convert individual date and time components to ISO 8601 DTC
----------------------------------------------------------------------------------------- 

Revision History:
Date:             2025-01-20
Modification:     Updates to allow for spaces in dates of the form 'DD MON YYYY' 
                  Convert long month names to 3 character abbreviation
                  Added some additional user-defined messages if there is an invalid component
Modifier: 
----------------------------------------------------------------------------------------- 

NOTE: This is retrieved from https://github.com/rwatson724/Programming-Code-From-Papers/users_funcs_ISO_DATES.sas
****************************************************************************************/
libname fcmp 'C:\Desktop\GitHub\Programming-Code-From-Papers';

proc fcmp outlib = fcmp.funcs.ISO_date;
   /* need to zero fill each non-missing month, day, hour, minute, second */
   subroutine zfill(_comp $);
      outargs _comp;
      if not missing(_comp) and not( notdigit(cats(_comp)) ) then do;
         if lengthn(strip(_comp)) <= 2 then _comp  = put(input(_comp, best.), Z2.);
         else if lengthn(strip(_comp)) > 2 then do;
           put %sysfunc(compress("WARN ING:")) _comp "has is an invalid date/time component.";
           _comp = '-';
         end;
      end;
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

   function ISODTTM(dattim $) $; /* all inputs are character so need $ after input argument */
      /* for all character variables in the function, need to specify the length */
      length __dtc __dttm $20 iso_dtc $10 iso_tmc $8 year $4 month $2 day $2 __dtpart __tmpart $50 __newdt $200;

      /* convert all  the long month names to 3 characters and remove the comma if there is a comma in the date */
      /* Note for sake of future processing 'OCT' is 'OC+' and will be change to 'OCT' after processing */
      __newdt = prxchange('s/(APR)(?:Il)/APR/i', 1, prxchange('s/(MAR)(?:CH)/MAR/i', 1, prxchange('s/(FEB)(?:RUARY)/FEB/i', 1, prxchange('s/JAN(?:UARY)/JAN/i', 1, upcase(dattim)))));
      __newdt = prxchange('s/(SEP)(?:TEMBER)/SEP/i', 1, prxchange('s/(AUG)(?:UST)/AUG/i', 1, prxchange('s/(JUL)(?:Y)/JUL/i', 1, prxchange('s/(JUN)(?:E)/JUN/i', 1, __newdt))));
      __newdt = prxchange('s/(DEC)(?:EMBER)/DEC/i', 1, prxchange('s/(NOV)(?:EMBER)/NOV/i', 1, prxchange('s/OCT(?:OBER)|OCT/OC+/i', 1, prxchange('s/SEP(?:T)/SEP/i', 1, __newdt))));
      __newdt = compbl(translate(__newdt, ' ', ','));
      
      /* extract the time component if one exists */
      __stpos = prxmatch('/T|:/', __newdt);
      __numspc = countc(strip(__newdt), ' ');

      if __numspc ne 0 then do;
         if prxmatch('/\d{4}:\d{2}/', __newdt) then __stpos = __stpos + 1;
         else if prxmatch('/\s\d{2}:|\s\d{1}:|\s\D{2}:/', __newdt) then __stpos = __stpos - 2;
      end;

      if __stpos > 0 then __tmpart = substr(__newdt, __stpos);
      else call missing(__tmpart);
      
      /* extract the date component if one exists */
      x = find(__newdt, __tmpart, 't') - 1;
      if not missing(__tmpart) and x > 0 then __dtpart = substr(strip(__newdt), 1,  x);
      else if not missing(__tmpart) and x = 0 then call missing(__dtpart);
      else __dtpart = __newdt;

      if first(strip(reverse(__dtpart))) in ('T' ':') then __dtpart = substr(strip(__dtpart), 1, length(strip(__dtpart)) - 1);

      if first(strip(upcase(__tmpart))) = 'T' then __tmpart = substr(strip(__tmpart), 2);
      if first(strip(__tmpart)) = ':' then do;
         if prxmatch('/\d{2}:\d{2}|\d:\d{2}/', __tmpart) then __tmpart = substr(strip(__tmpart), 2);
         else __tmpart = cats('UN', __tmpart);
      end;

      /* need to do pre processing to flip month and day if month is first */
      if not missing(__dtpart) then __tempmo = upcase(substr(strip(__dtpart), 1, 3));
      if __tempmo in ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC') then do;
         __tmo = upcase(substr(scan(__dtpart, 1, ' ,'), 1, 3));
         /* assuming that if the numbers following a month is 4 characters then it is a year and day is missing */
         if length(scan(__dtpart, 2, ' ,-/')) = 4 then do;
            __tyr = scan(__dtpart, 2, ' ,-/');
            __tdy = 'UN';
         end;
         /* if the second token is a valid number then need to determine if it is a day or year -- if a valid day assume it is day otherwise assume it is a year */
         else if input(scan(__dtpart, 2, ' -/'), best.) ne . then do;  /****************?? best. ***********/
            __tdt = day(intnx('month', input(resolve( '%sysevalf(' || cats("'01", __tmo, "2025'd") || ')' ), best.), 0, 'E'));
            if . < input(scan(__dtpart, 2, ' ,-/'),  best.) <= __tdt then do;
                __tdy = scan(__dtpart, 2, ' ,-/');
                if missing(input(scan(__dtpart, 3, ' ,-/'), best.)) then __tyr = 'UNKN';
                else __tyr = scan(__dtpart, 3, ' ,-/');
            end;
            else do;
                __tdy = 'UN';
                __tyr = scan(__dtpart, 2, ' ,-/');
            end;
         end;
         __dtpart = cats(__tdy, __tmo, __tyr);
      end;
      
      /* compress any spaces and delimiters typically used in dates - should only have numbers and characters */
      /* convert the '+' used to mask the 'T' in 'OCT' but to a 'T'                                           */
      __dtpart = translate(compress(__dtpart, ' -/'), 'T', '+');

      __dmy = prxmatch('/\A\d{1,2}\D{3}\d{2,4}|\A\D{1,5}\d{2,4}/', strip(__dtpart));
      __dmo = prxmatch('/\A\d{1,2}\D{3}|\A\D{1,5}/', strip(__dtpart));
      __myr = prxmatch('/\A\D{3}\d{2,4}|\A\D{3,5}\d{2,4}/', strip(__dtpart));
      /* date is in DDMONYY, DDMONYYYY, DMONYY, DDMONYYYY format and need to extract components */
      if (__dmy or __dmo or __myr) then do;
         if __dmy or __myr then year = substr(__dtpart, findc(__dtpart, '', 'a', -1*length(strip(__dtpart))) + 1);
         else if __dmo then year = 'UNK';

         if anydigit(first(strip(__dtpart))) then do;
            day = substr(strip(__dtpart), 1, anyalpha(strip(__dtpart)) - 1);
            __mo  = substr(strip(__dtpart), anyalpha(strip(__dtpart)), 3);
         end;
         else do;
            if prxmatch('/JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC/i', __dtpart) then do;
               __prst = prxmatch('/JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC/i', strip(__dtpart));            
               __mo = substr(strip(__dtpart), __prst, 3);
               if __prst > 1 then day = substr(strip(__dtpart), 1, __prst - 1);
               else day = 'UN';
            end;
            else do;
               __mo = 'UN';
               day = 'UN';
            end;
         end;
      end;
      /* entire date is character so day and year are unknown - month can be 3-character month or unknown */
      else if not(anydigit(strip(__dtpart))) then do;
         year = 'UNK';
         day = 'UN';
         if prxmatch('/JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC/i', __dtpart) then do;
            __prst = prxmatch('/JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC/i', __dtpart);            
            __mo = substr(strip(__dtpart), __prst, 3);
         end;
         else __mo = 'UN';
      end;
      /* entire date is numeric so depending on the length will assume a specific format or assume not enough info to determine */
      else do;
         if length(strip(__dtpart)) = 8 then do;
            year = strip(substr(__dtpart, 1, 4));
            __mo = strip(substr(__dtpart, 5, 2));
            day = strip(substr(__dtpart, 7, 2));
         end;
         else if prxmatch('/\d{4-6}\D{2-4}/i', __dtpart) then do;
            year = strip(substr(__dtpart, 1, 4));
            if lengthn(strip(__dtpart)) > 4 and anyalpha(substr(strip(__dtpart), 5, 1)) then __mo = 'UN';
            if lengthn(strip(__dtpart)) > 6 and anyalpha(substr(strip(__dtpart), 7, 1)) then __mo = 'UN';
         end; 
         else if lengthn(strip(__dtpart)) = 0 then call missing(year, month, day);
         else do;
            if length(strip(__dtpart)) = 4 and not(anyalpha(__dtpart)) then
              put %sysfunc(compress("WARN ING:")) dattim "insufficient to determine if date part represents YYYY or DDMM or MMDD.";
            else if length(strip(__dtpart)) in (5 6) and not(anyalpha(__dtpart)) then 
              put %sysfunc(compress("WARN ING:")) dattim "insufficient to determine if date part represents DDMMM or YYYYM or YYMMDD or YYYYMM or MMDDYY.";
            else
              put %sysfunc(compress("WARN ING:")) dattim "date part not in a usable format.";
            __dtc = '_ERROR_';
            return(__dtc);
         end;          
      end;

      if __mo in ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC') then 
            month = put(whichc(strip(__mo), 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'), Z2.);
      else month = __mo;

      /* extract time portion to see if hh:mm:ss (assume 24-hr clock) or if HH:MM:SS AM/PM (12-hr clock) */      
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