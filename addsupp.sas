/****************************************************************************************
Program:          addsupp.sas
Protocol:         Study A
SAS Version:      9.4
Developer:        Richann Watson 
Date:             10NOV2023 
Purpose:          Merge SUPP data with parent data
Operating Sys:    Windows 11
Macros:           NONE
Input:            dsn - name of parent data set
Output:           temporary data set that has supp data added to parent data
Validation Ready: N/A
Validated by:
Date Validated:
Comments:
----------------------------------------------------------------------------------------- 

Revision History:
Date: 
Requestor: 
Modification: 
Modifier: 

****************************************************************************************/
%macro addsupp(dsn = , specfnm = , specloc = );
   %global gmacvar;

   /* need to remove all existing global suppqual macro variables upon invocation */
   /* this is to prevent suppqual values from being carried to other executions   */
   proc sql noprint;
      select NAME into :gmacvar separated by ' '
      from DICTIONARY.MACROS
      where SCOPE = 'GLOBAL' and (NAME ? 'QNAM');
   quit;
   
   %if %bquote(&gmacvar) ne   %then %do;
      %symdel &gmacvar gmacvar;
   %end;

   %global qnamvars qnamvarsc qnamlbls; 

   /*** BEGIN SECTION TO RETRIEVE THE CODELIST FOR QNAM/QLABEL FOR SUPP FROM THE SDTM SPECS ***/
   /* if SDTM spec filename and/or location are not provided then use defaults */
   %if %bquote(&specfnm) = %then %let specfnm = SDTM_Specs; ;
   %if %bquote(&specloc) = %then %let specloc = &protroot.Data\SDTM\Specifications; ;

   /* assign libname to read in the SDTM specs - if libname cannot be assigned then write message to log and default macro variables to null */
   libname SDTMSPEC xlsx "&specloc\&specfnm..xlsx";
   %if %sysfunc(libref(SDTMSPEC)) = 0 %then %do;
      data suppct;
         set SDTMSPEC."Codelists"n;
         where upcase(CODELIST) ? upcase("SUPP&dsn.QNAM") and upcase(STATUS) = 'KEEP';
         keep CODELIST SUBMISSION_VALUE DECODE_VALUE;
      run;

      /* need to see if a codelist of the the SUPP data set is in specs - if not then write message to log */
      %let dsid = %sysfunc(open(suppct));
      %let cnt = %sysfunc(attrn(&dsid, nobs));
      %let rc = %sysfunc(close(&dsid));

      %if &cnt > 0 %then %do;
         proc sql noprint;
            select SUBMISSION_VALUE,
                   SUBMISSION_VALUE,
                   catx(' = ', SUBMISSION_VALUE, quote(strip(DECODE_VALUE)))
                   into
                   :qnamvars separated by ' ',
                   :qnamvarsc separated by ', ',
                   :qnamlbls separated by ' '
            from suppct;
         quit;            
      %end;
      %else %do;
         %put %sysfunc(compress(W ARNING:)) No codelist for QNAM for SUPP&dsn in SDTM specifications. Expected name of codelist is SUPP&dsn.QNAM;
      %end;
   %end;
   %else %do;
      %put %sysfunc(compress(W ARNING:)) SDTM specifications are not available;
      %let qnamvars =;
      %let qnamlbls =;
   %end;
   libname SDTMSPEC clear;

   /* check to see if the SUPP data sets exists - if it does not exist then default count to 0 */
   %if %sysfunc(exist(SDTM.SUPP&dsn)) %then %do;
       proc sort data = SDTM.SUPP&dsn out = __supp&dsn;
          by IDVAR;
       run;

      /* need to see if a SUPP data set contains observations and set count to number of observations */
      %let dsid = %sysfunc(open(__supp&dsn));
      %let scnt = %sysfunc(attrn(&dsid, nobs));
      %let rc = %sysfunc(close(&dsid));
   %end;
   %else %let scnt = 0; ;

   /* if count is greater than 0 then process the SUPP data set otherwise default to parent and tack on the expected variables based on the specs */
   %if &scnt > 0 %then %do;

     /* determine what the IDVARS are used in SUPP and the data type and length */
     proc sort data = __supp&dsn out = supprsids (keep = IDVAR) nodupkey;
        by IDVAR;
     run;

     proc sql noprint;
        create table __&dsn.vars as
       select NAME, TYPE, LENGTH
       from DICTIONARY.COLUMNS
       where upcase(LIBNAME) = 'SDTM' and upcase(MEMNAME) = upcase("&dsn")
       order by NAME;
     quit;

     data _null_;
          merge __&dsn.vars
              supprsids (rename = (IDVAR = NAME)
                         in = insupp);
       by NAME;
       if insupp;

       length __len $10;
       if upcase(TYPE) = 'CHAR' then __len = cats('$', LENGTH);
       else __len = cats(LENGTH);
         __typ = whichc(first(upcase(TYPE)), 'C', 'N');

       call symputx(cats(NAME, '_len'), __len);
       call symputx(cats(NAME, '_typ'), __typ);
     run;

      data _null_;
         set __supp&dsn end = eof;
         by IDVAR;
         length byvars $200 byvar $8;
         retain byvars;
         if first.IDVAR then do;
            if missing(IDVAR) then byvar = 'NONE';
            else byvar = IDVAR;
            byvars = catx(' ', byvars, byvar);
            call execute(cat("data ", byvar, "(drop = IDVAR:); set SDTM.SUPP&dsn.;"));
            call execute(cat("where IDVAR = ", quote(IDVAR), ";"));
            if not missing(IDVAR) then do;
            call execute(cat("length ", strip(IDVAR), " &", strip(IDVAR), "_len;"));
            call execute(cat('if &', strip(IDVAR), "_typ = 1 then ", IDVAR, " = IDVARVAL;"));
            call execute(cat('else if &', strip(IDVAR), "_typ = 2 then ", IDVAR, " = input(IDVARVAL, best.); "));
            end;
            call execute("run;");
         end;
         if eof;
         call symputx('byvars', byvars); 
      run;

      %put &=byvars;
          
      %do i = 1 %to %sysfunc(countw(&byvars));
         %let __by = %scan(&byvars, &i);
         %let __bydsn = &__by;

         %if &__by = NONE %then %let __by =;;

         proc sort data = %if &i = 1 %then SDTM.&dsn out = &dsn.0; %else &dsn.%eval(&i-1); presorted;
            by USUBJID &__by;
         run;

         proc sort data = &__bydsn;
            by USUBJID &__by;
         run;

         proc transpose data = &__bydsn
                        out = t&__bydsn (drop = _:);
            by USUBJID &__by;
            var QVAL;
            id QNAM;
            idlabel QLABEL;
         run;

         data &dsn.&i;
            merge t&__bydsn &dsn.%eval(&i-1);
            by USUBJID &__by;
         run;
      %end;

      /* create a data set that has a consistent naming convention so that if &i changes then don't have to try and remember what last number was */
      data &dsn._supp;
         retain USUBJID;
         if 0 then do;
            %if %bquote(&qnamvars) ne  %then %do;
               length &qnamvars. $200;
               call missing(&qnamvarsc);
            %end;
         end;
         set _last_;
         label &qnamlbls;
      run;
    %end;
    %else %do;
       data &dsn._supp;
          set SDTM.&dsn.;
          %if %bquote(&qnamvars) ne  %then %do;
             length &qnamvars $200;
             call missing(&qnamvarsc);
             label &qnamlbls;
          %end;
       run;
    %end;
%mend addsupp;