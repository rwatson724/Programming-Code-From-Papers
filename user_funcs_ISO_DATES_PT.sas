/****************************************************************************************
Program:          FN_ISODTMPT.sas
SAS Version:      SAS 9.4m7
Developer:        Richann Watson 
Date:             2022-06-04 
Operating Sys:    Windows 10
Purppose:         User-defined function that will convert individual date and time components to ISO 8601 DTC
----------------------------------------------------------------------------------------- 

Revision History:
Date:             2025-01-15
Modification:     Changed name of function to align with name of other user-defined function
Modifier: 
----------------------------------------------------------------------------------------- 

NOTE: This is retrieved from https://github.com/rwatson724/Programming-Code-From-Papers/users_funcs_ISO_DATES_PT.sas
****************************************************************************************/
libname fcmp 'C:\Desktop\GitHub\Programming-Code-From-Papers';

proc fcmp outlib = fcmp.funcs.ISO_DATES_PT;
 
   function isodtmpt(mn $, dy $, yr $, hr $, mi $, sc $) $;  /* all inputs are character so need $ after input argument */
      length NEWDTC newdttm $20 isodt $10 isotm $8;  /* for all character variables in function need to specify length */
 
      /* use new variables to be build ISO 8601 date time */
      isodt = catx("-", yr, mn, dy);
      isotm = catx(":", hr, mi, sc);
 
      put(isodt);  /* used for debugging - want to see what is being created */
 
      /* if time is nothing but '-' and ':' then default to blank */
      /* if it there is so numeric portion of the time then keep  */
      /* up throught he last time element that had a numeric part */
      if notpunct(strip(isotm)) > 0 then
          _isotm = substr(isotm, 1, notpunct(strip(isotm), -length(isotm)));
      else _isotm = ' ';
 
      /* combine time with date to build ISO datetime */
      newdttm = catx("T", isodt, _isotm);
 
      /* if there is no time portion then keep only up */
      /* through last numeric portion of date          */
      if anyalpha(strip(newdttm)) > 0 then NEWDTC = newdttm;
      else if notpunct(strip(newdttm)) > 0 then
          NEWDTC = substr(newdttm, 1, notpunct(strip(newdttm), -length(newdttm)));
      else NEWDTC = ' ';
 
      return(NEWDTC);
   endfunc;
quit;