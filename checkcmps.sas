/****************************************************************************************
Program:          checkcmps.sas
Protocol:         Study A
SAS Version:      9.4
Developer:        Richann Watson 
Date:             04JAN2017 
Purpose:          Check the lst of an individual file or to check the lsts in a directory. 
                  Determine if PROC COMPARE ran clean in QC
Operating Sys:    Windows 8
Macros:           NONE
Input:            lst files
Output:           PROC COMPARE Report
Validation Ready: N/A
Validated by:
Date Validated:
Comments:
----------------------------------------------------------------------------------------- 

Revision History:
Date: 20MAR2017
Requestor: Maintenance
Modification: Need to account for multiple PROC COMPARE in one output
Modifier: Richann Watson

Date: 29JUN2017
Requestor: Maintenance
Modification: Allow for compare output to be stored in multiple locations
Modifier: Richann Watson

Date: 16NOV2018
Requestor: Maintenance
Modification: Change 'abort abend' to '%abort'.
Modifier: Richann Watson
----------------------------------------------------------------------------------------- 
****************************************************************************************/

/* retrieve all the compare files in the specified directory */
%macro checkcmps(loc=,  /* location of where the compare files are stored   */
                        /* can add multiple locations but they need to be   */
                        /* separated by the default delimiter '@' or the    */
                        /* user specified delimiter                         */
                 loc2=, /* location of where report is stored (optional)    */
                 fnm=,  /* which types of files to look at (optional)       */
                        /* e.g., Tables – t_, Figures – f_, Listings – l_   */ 
                        /* separate types of files by delimiter indicated in*/
                        /* the delm macro parameter (e.g., t_@f_)           */
                 delm=@,/* delimiter used to separate types of files (opt'l)*/
                 out=   /* compare report name (optional)                   */);
             
  /* need to determine the environment in which this is executed   */
  /* syntax for some commands vary from environment to environment */
  %if &sysscp = WIN %then %do;
    %let ppcmd = %str(dir);
    %let slash = \;
  %end;
  %else %if &sysscp = LIN X64 %then %do;
    %let ppcmd = %str(ls -l);
    %let slash = /;
  %end;
  /* end macro call if environment not Windows or Linux/Unix */
  %else %do;
    %put ENVIRONMENT NOT SPECIFIED;
    %abort;
  %end;

  /* if a filename is specified then build the where clause */
  %if &fnm ne   %then %do;  /* begin conditional if "&fnm" ne "" */
    data _null_;
     length fullwhr $2000.;
      retain fullwhr;

     /* read in each compare file and check for undesired messages */
     %let f = 1;
     %let typ = %scan(&fnm, &f, "&delm");

     /* loop through each type of filename to build the where clause */
     /* embed &typ in double quotes in case filename has special characters or spaces */
     %do %while ("&typ" ne "");  /* begin do while ("&typ" ne "") */

        partwhr = catt("index(flst, '", "&typ", "')");
        fullwhr = catx(" or ", fullwhr, partwhr);

        call symputx('fullwhr', fullwhr);

         %let f = %eval(&f + 1);
        %let typ = %scan(&fnm, &f, "&delm");
      %end;  /* end do while ("&typ" ne "") */

    run;
  %end;  /* end conditional if "&fnm" ne "" */

  /* 20170629 - richann - need to make sure data sets do not exist before start processing */
  proc datasets;
     delete alllsts alluv report report_1 report_2 report_3;
  quit;

  /* 20170629 - richann - need to process each location for compare files separately */
  %let g = 1;
  %let lcn = %scan(&loc, &g, "&delm");

  /* 20170629 - richann - create a default location for report if report location not specified */
  %let dloc = &lcn; 

  /* 20170629 - richann - need to make sure the location exists so create a temp library */
  libname templib&g "&lcn";

  /* 20170629 - richann - begin looking through each compare file location for specified types */
  /*                      if &SYSLIBRC returns a 0 then path exists                            */
  %do %while ("&lcn" ne "" and &syslibrc = 0);  /* begin do while ("&lcn" ne "" and &syslibrc = 0) */

    /* need to build pipe directory statement as a macro var  */
    /* because the statement requires a series of single and  */
    /* double quotes - by building the directory statement    */
    /* this allows the user to determine the directory rather */
    /* than it being hardcoded into the program               */
    /* macro var will be of the form:'dir "directory path" '  */
    /* 20170629 - richann - change &loc to &lcn to allow for different locations */
    data _null_;
      libnm = strip("&lcn");
      dirnm = catx(" ", "'", "&ppcmd", quote(libnm), "'");
      call symputx('dirnm', dirnm);
    run;

    /* read in the contents of the directory containing the lst files */
    filename pdir pipe &dirnm lrecl=32727;

    data lsts&g (keep = flst fdat ftim filename numtok);
      infile pdir truncover scanover;
      input filename $char1000.;

     length flst $50 fdat ftim $10;

      /* keep only the compare files */
     if index(filename, ".lst");

      /* count the number of tokens (i.e., different parts of filename) */
     /* if there are no spaces then there should be 5 tokens           */
     numtok = countw(filename,' ','q');

     /* parse out the string to get the lst keep only filename */
     /* note on scan function a negative # scans from the right*/
     /* and a positive # scans from the left                   */
     /* need to build the flst value based on number of tokens */
     /* if there are spaces in the lst name then need to grab  */
     /* each piece of the lst name                             */
     /* the first token that is retrieved will have '.lst' and */
     /* it needs to be removed by substituting a blank         */

     /* entire section below allows for either Windows or Unix */
     /*********** WINDOWS ENVIRONMENT ************/
     /* the pipe will read in the information in */
     /* the format of: date time am/pm size file */
     /* e.g. 08/24/2015 09:08 PM 18,498 ae.lst   */
     /*    '08/24/2015' is first token from left */
     /*    'ae.lst' is first token from right    */
     %if &sysscp = WIN %then %do;  /* begin conditional if &sysscp = WIN */
       /* 20170629 - richann - move creation of flst within conditional if */
       do j = 5 to numtok;
         tlst = tranwrd(scan(filename, 4 - j, " "),  ".lst", "");
         flst = catx(" ", tlst, flst);
       end;
        ftim = catx(" ", scan(filename, 2, " "), scan(filename, 3, " "));
       fdat = put(input(scan(filename, 1, " "), mmddyy10.), date9.);
      %end;  /* end conditional if &sysscp = WIN */
   
     /***************************** UNIX ENVIRONMENT ******************************/
     /* the pipe will read in the information in the format of: permissions, user,*/
     /* system environment, file size, month, day, year or time, filename         */
     /* e.g. -rw-rw-r-- 1 userid sysenviron 42,341 Oct 22 2015 ad_adaapasi.lst    */
     /*    '-rw-rw-r--' is first token from left                                  */
     /*    'ad_adaapasi.lst' is first token from right                            */
     %else %if &sysscp = LIN X64 %then %do;  /* begin conditional if &sysscp = LIN X64 */
       /* 20170629 - richann - move creation of flst within conditional if */
       do j = 9 to numtok;
         tlst = tranwrd(scan(filename, 8 - j, " "),  ".lst", "");
         flst = catx(" ", tlst, flst);
       end;

       _ftim = scan(filename, 8, " ");

       /* in Unix if year is current year then time stamp is displayed */
       /* otherwise the year last modified is displayed                */
       /* so if no year is provided then default to today's year and if*/
       /* no time is provided indicated 'N/A'                          */
        if anypunct(_ftim) then do;
          ftim = put(input(_ftim, time5.), timeampm8.);
          yr = put(year(today()), Z4.);
        end;
        else do;
          ftim = 'N/A';
          yr = _ftim;
        end;

        fdat = cats(scan(filename, 7, " "), upcase(scan(filename, 6, " ")), yr);
     %end;  /* end conditional if &sysscp = LIN X64 */
    run;

    /* create a list of lsts, dates, times and store in macro variables */
   /* 20170629 - richann - count number of compare files in the specified folder and retain in macro variable */
    proc sql noprint;
      select flst,
             fdat, 
             ftim,
          count (distinct flst)
             into : currlsts separated by "&delm",
                : currdats separated by " ",
               : currtims separated by "@",
              : cntlsts
      from lsts&g
      %if &fnm ne   %then where &fullwhr;     ; /* need to keep extra semicolon */
    quit;

    /* need to make sure the alllsts data set does not exist before getting into loop */
   /* 20170626 - richann - due to multiple locations now allowed this needs to be moved to an outer loop */
   /*
    proc datasets;
       delete alllsts;
    quit;
   */

   /* 20170629 - richann - only loop through the directory if the number of compare file found is greater than 0 */
   %if &cntlsts ne 0 %then %do;  /* begin conditional if &cntlsts ne 0 */

      /* read in each lst file and check to see various components of PROC COMPARE */
      %let x = 1;
      %let lg = %scan(&currlsts, &x, "&delm");
      %let dt = %scan(&currdats, &x);
      %let tm = %scan(&currtims, &x, '@');

      /* loop through each compare file in the directory and look for undesirable messages */
      /* embed &lg in double quotes in case filename has special characters or spaces      */
      %do %while ("&lg" ne "");  /* begin do while ("&lg" ne "") */
        /* read the compare file into a SAS data set to parse the text */
       /* 20170629 - richann - need to keep two separate data sets for separate processing */
        data lstck&g&x (drop = varvalne)
             uvck&g&x (keep = lst: comp: base: section label varvalne diffattr);
        /* 20170629 - richann - change missover to truncover to avoid truncation */
          /*                      change &loc to &lcn to allow for different locs  */
         infile "&lcn.&slash.&lg..lst" /*missover*/truncover pad end=eof;

        /* 20170629 - richann - change $2000 to $char2000 in order to maintain spacing so that we can get correct line number */
         input line $char2000.;

         /* 20170320 - richann - need keep a counter of number of comparisons */
          /*                      in lst file in case there is more than one   */
         if _n_ = 1 then compnum = 0;

         length basedsn compdsn $40 lstlc $200;
        /* 20170629 - richann - add dfsum to see if there are any common vars with different attributes  */
          /*                      add unsum to keep track if there are variable with unequal values/results*/
         retain basedsn compdsn dssum vrsum dfsum obsum vlsum uvsum ursum lablpres compnum;

         lstlc = "&lcn";
         label lstlc = 'Compare Location';

         /* need to look for the start of the PROC COMPARE */
         if index(upcase(line), 'THE COMPARE PROCEDURE') then do;
           basedsn = '';
           compdsn = '';
         end;

         /* determine the data sets used for comparison */
         if basedsn = '' and compdsn = '' and index(upcase(line), 'COMPARISON OF') and 
           index(upcase(line), 'WITH') then do;
           basedsn = scan(line, 3, " ");
           compdsn = scan(line, -1, " ");
         end;

         /* 20170320 - richann - increment number of comparison counter by one every */
          /*                      time encounter a new 'THE COMPARE PROCEDURE'        */
         if index(upcase(line), 'DATA SET SUMMARY') then do;      
          compnum + 1;
         end;

         /* set flags to know which part of PROC COMPARE looking at */
        /* 20170629 - richann - add sct5 to check if there are Variables with Unequal Values */
        /*                      add sct6 to indicate start of portion where display unequals */
        /*                      add sct7 to indicate start of differing attributes           */
        /*                      moved 'SUMMARY' from index statement in macro to part of the */
        /*                      macro call since not alll sections contain the word 'SUMMARY'*/
         %macro compsect(str = , sct1 = , sct2 = , sct3 =, sct4 =, sct5 =, sct6 =, sct7=);
           if index(upcase(line), "&str") then do;
             &sct1.sum = 1;
            &sct2.sum = .;
            &sct3.sum = .;
            &sct4.sum = .;
           &sct5.sum = .;
           &sct6.sum = .;
           &sct7.sum = .;
           end;
         %mend compsect;

         %compsect(str = DATA SET SUMMARY,              sct1 = ds, sct2 = vr, sct3 = ob, sct4 = vl, sct5 = uv, sct6 = ur, sct7 = df)
         %compsect(str = VARIABLES SUMMARY,             sct1 = vr, sct2 = ds, sct3 = ob, sct4 = vl, sct5 = uv, sct6 = ur, sct7 = df)
         %compsect(str = DIFFERING ATTRIBUTES,          sct1 = df, sct2 = vr, sct3 = ds, sct4 = ob, sct5 = vl, sct6 = uv, sct7 = ur)
         %compsect(str = OBSERVATION SUMMARY,           sct1 = ob, sct2 = vr, sct3 = ds, sct4 = vl, sct5 = uv, sct6 = ur, sct7 = df)
         %compsect(str = VALUES COMPARISON SUMMARY,     sct1 = vl, sct2 = vr, sct3 = ob, sct4 = ds, sct5 = uv, sct6 = ur, sct7 = df)
         %compsect(str = VARIABLES WITH UNEQUAL VALUES, sct1 = uv, sct2 = ds, sct3 = vr, sct4 = ob, sct5 = vl, sct6 = ur, sct7 = df)
         %compsect(str = VALUE COMPARISON RESULTS FOR,  sct1 = ur, sct2 = ds, sct3 = vr, sct4 = ob, sct5 = vl, sct6 = uv, sct7 = df)

         /* need to determine if there is a label provided on the data sets being compared */
         if dssum = 1 and index(upcase(line), 'NVAR') and index(upcase(line), 'NOBS') and index(upcase(line), 'LABEL') then lablpres = 'Y';
     
         length section $50 type $10 label $10 value $40 lstnm $25 lstdt lsttm $10;

         /* create variables that will contain the compare file that is being scanned */
         /* as well as the and date and time that the compare file was created        */
         lstnm = upcase("&lg");
         lstdt = "&dt";
         lsttm = "&tm";

         %macro basecomp(type = );       
          type = "&type";

            /* determine number of variables and number of observations in each data set */
           if dssum = 1 then do;
            section = 'Data Set Summary';
           /* 20170629 - richann - it is possible for the DEV and QC to have a similar name */
           /*                      so need to make sure it only matches one so scan for the */
           /*                      data set name instead of using index                     */
             if /*index(upcase(line), strip(%upcase(&type.dsn)))*/
                 strip(scan(line, 1, ' ')) = strip(%upcase(&type.dsn)) then do;   
                label = 'NumVar'; 
                value = scan(line, 4, " ");
             output lstck&g&x;

             label = 'NumObs';
             value = scan(line, 5, " ");
             output lstck&g&x;

             /* if there should be a label then need to build based on number of tokens */
                if lablpres = 'Y' then do;
                  numtok = countw(line, ' ', 'q');
              label = 'DSLbl';
              value = ''; /* need to reset to null so it values from previous records are not carried forward */

                  do k = 6 to numtok;
                   value = catx(" ", value, scan(line, k + 1));
              end; /* end do k = 6 */
              output lstck&g&x;
               end; /* end lablpres = 'Y' */
            end; /* end index(upcase(line), strip ... */
           end; /* end dssum = 1 */

           /* see how many variabes are in one data set but not other */
           if vrsum = 1 and index(upcase(line), 'NUMBER OF VARIABLES IN') and 
               index(upcase(line), 'BUT NOT IN') and
               scan(line, 5, ' ') = strip(%upcase(&type.dsn)) then do;
           section = 'Variables Summary';
           label = 'VarsIn';
              value = scan(line, -1);
           output lstck&g&x;
          end; /* end vrsum = 1 and index(upcase(line), 'NUMBER OF VAR ... */

            /* determine number of observations in common */
         /* 20170629 - richann - it is possible for the DEV and QC to have a similar name */
         /*                      so need to make sure it only matches one so scan for the */
         /*                      data set name instead of using index                     */
           if obsum = 1 then do;
            section = 'Observation Summary';
              if index(upcase(line), 'TOTAL NUMBER OF OBSERVATIONS READ') and
                 /*index(line, strip(%upcase(&type.dsn)))*/
                 strip(tranwrd(scan(line, 7, ' '), ':', '')) = strip(%upcase(&type.dsn)) then do;
             label = 'ObsRead';
                value = scan(line, -1);
             output lstck&g&x;
           end; /* end index(upcase(line), 'TOTAL NUMBER ... */
            if index(upcase(line), 'NUMBER OF OBSERVATATIONS IN') and index(upcase(line), 'BUT NOT IN') and
              scan(line, 5, ' ') = strip(%upcase(&type.dsn)) then do;
             label = 'ObsIn';
                value = scan(line, -1);
              output lstck&g&x;
           end; /* end index(upcae(line), 'NUMBER OF OBS ... */
            if index(upcase(line), 'NUMBER OF DUPLICATE OBSERVATIONS') and
                 /*index(line, strip(%upcase(&type.dsn)))*/
                 strip(tranwrd(scan(line, 7, ' '), ':', '')) = strip(%upcase(&type.dsn)) then do;
             label = 'DupObs';
                value = scan(line, -1);
              output lstck&g&x;
           end; /* end index(upcase(line), 'NUMBER OF DUP ... */
          end; /* end obsum = 1 */
         %mend basecomp;

         %basecomp(type = base)
         %basecomp(type = comp)

         /* these only need to be output once so done outside of macro */

         /* see how many variabes are in common and how with have      */
         /* different data types (i.e., character versus numeric)      */                   
         if vrsum = 1 then do;
           if index(upcase(line), 'NUMBER OF VARIABLES IN COMMON') then do;
            type = 'Common';
           section = 'Data Set Summary'; /* although this is in Var Summary wnat to compare with values in Data Set Summary */
           label = 'NumVar';
              value = scan(line, -1);
             output lstck&g&x;
           end; /* end index(upcase(line), 'NUMBER OF VAR ... COMMON') */    
          if index(upcase(line), 'NUMBER OF VARIABLES WITH CONFLICTING TYPES') then do;
            type = 'Conflict';
           section = 'Variables Summary';
           label = 'ConfType';
              value = scan(line, -1);
           output lstck&g&x;
          end; /* end index(upcase(line), 'NUMBER OF VAR ... CONFLICT ... */
         end; /* end vrsum = 1 */

         /* determine number of observations in common */
         if obsum = 1 then do;
          if index(upcase(line), 'COMPARED VARIABLES UNEQUAL') then do;
            type = 'ObsVarNE';
           section = 'Observation Summary';
           label = 'AllEq';
              value = scan(line, -1);
           output lstck&g&x;
          end; /* end index(upcase(line), 'COMPARED VAR ... */
           if index(upcase(line), 'COMPARED VARIABLES EQUAL') then do;
            type = 'Common';
           section = 'Data Set Summary'; /* although this is in Obs Summary want to compare with values in Data Set Summary */
           label = 'NumObs';
              value = scan(line, -1);
           output lstck&g&x;

           /* want 3 records for this so it can be compared to data set summary as well as the Obs Summary */
           section = 'Observation Summary';
           label = 'ObsRead';
           output lstck&g&x;

           label = 'AllEq';
           output lstck&g&x;
          end; /* end index(upcase(line), 'COMPARED ... */
          if index(line, 'No unequal values were found.') then do;
            type = 'ObsVarEq';
           section = 'Observation Summary';
           label = 'AllEq';
              value = 'Y';
           output lstck&g&x;
          end; /* end index(line, 'No unequal ... */
         end; /* end obsum = 1 */

         /* determine whether all results are equal or if there are different values for some variables */
         if vlsum = 1 then do; 
           if index(upcase(line), 'NUMBER OF VARIABLES COMPARED WITH ALL OBSERVATIONS EQUAL') then do;
            type = 'AllVarEq';
           section = 'Values Comparison Summary';
           label = 'NumVarVal';
              value = scan(line, -1);
           output lstck&g&x;
          end; /* end index(upcase(line), 'NUMBER OF VAR ... EQUAL') */
           if index(upcase(line), 'NUMBER OF VARIABLES COMPARED WITH SOME OBSERVATIONS UNEQUAL') then do;
            type = 'SomeVarNE';
           section = 'Values Comparison Summary';
           label = 'NumVarVal';
              value = scan(line, -1);
           output lstck&g&x;
           end; /* end index(upcase(line), 'NUMBER OF VAR ... UNEQUAL') */
           if index(upcase(line), 'TOTAL NUMBER OF VALUES WITH COMPARE UNEQUAL') then do;
              type = 'ValNE';
           section = 'Values Comparison Summary';
           label = 'NumVarVal';
              value = scan(line, -1);
           output lstck&g&x;
           end; /* end index(upcase(line), 'TOTAL NUMBER ... */
         if index(upcase(line), 'TOTAL NUMBER OF VALUES NOT EXACTLY EQUAL') then do;
              type = 'ValNEE';
           section = 'Values Comparison Summary';
           label = 'NumVarVal';
              value = scan(line, -1);
           output lstck&g&x;
         end; /* end index(upcase(line), 'TOTAL NUMBER OF VALUES NOT EXACTLY EQUAL') */
         end; /* end vlsum = 1 */

        /* 20170629 - richann - need to keep track of all the variables that have unequal values */
        /*                      this portion will be processed separately so variables will be   */
        /*                      slightly different than the rest of the variables in this step   */
        if uvsum = 1 then do; /* begin uvsum = 1 */
          if not(index(upcase(line), 'NDIF') or 
                   index(upcase(line), 'MAXDIF') or 
                   index(upcase(line), 'VARIABLES WITH UNEQUAL VALUES')) then do;
            section = 'Variables with Unequal Values';
            label = 'VarValNE';
            varvalne = scan(line, 1); 
            /* it is possible to have more than one variable with unequal values */
            /* so need to create a counter so that each record is unique         */
            if varvalne ne '' then do;
                 uvcnt + 1;
                 output uvck&g&x;
            end;
         end;
        end; /*  end uvsum = 1 */
        
        /* 20170629 - richann - determine if there are variables with different attributes */
        if dfsum = 1 then do; /* begin dfsum = 1 */
          retain colhdr;
         if index(upcase(line), 'VARIABLE') then colhdr = index(upcase(line), 'VARIABLE');
            if not(index(upcase(line), 'VARIABLE')) then varloc = anyalpha(line);
         if colhdr = varloc then do;
            section = 'Listing of Common Variables with Differing Attributes';
            label = 'DiffAttr';
            diffattr = scan(line, 1, ' ');
            dfcnt + 1;
            output uvck&g&x;
         end;
          
        end; /* end dfsum = 1 */
       run;

       /* append all the results into one data set */
       /* 20170629 - richann - since allowing for multiple locations no longer base criterion off of &x = 1*/
       /*                      need to check to see if data set exists - during first iteration it should  */
       /*                      not exist because it was deleted at top of program                          */
       %let exist = %sysfunc(exist(alllsts));
       %if /*&x = 1*/ &exist = 0 %then %do;
         data alllsts;
           set lstck&g&x;
         run;
       %end;
       %else %do;
         proc append base=alllsts
                      new=lstck&g&x;
         run;
       %end;

      /* 20170629 - richann - create a data set that contains all vars with unequal values */
       %let uvexist = %sysfunc(exist(alluv));
       %if &uvexist = 0 %then %do;
         data alluv;
           set uvck&g&x;
         run;
       %end;
       %else %do;
         proc append base=alluv
                      new=uvck&g&x;
         run;
       %end;
       %let x = %eval(&x + 1);
       %let lg = %scan(&currlsts, &x, "&delm");
       %let dt = %scan(&currdats, &x);
       %let tm = %scan(&currtims, &x, '@');
     %end;  /* end do while ("&lg" ne "") */

   %end;  /* end conditional if &cntlsts ne 0 */

    /* 20170606 - richann - end portion to loop through all locations */
    %let g = %eval(&g + 1);
    %let lcn = %scan(&loc, &g, "&delm");

    /* 20170626 - richann - need to make sure the location exists so create a temp library */
    libname templib&g "&lcn";
  %end;  /* end

  /* since a list of files can be provided then the files may not be in order */
  /* 20170320 - richann - add compnum to sort to avoid duplicates */
  /*                      if more than one PROC COMPARE in output */
  /* 20170629 - richann - need to include the compare location */
  proc sort data = alllsts presorted;
    by lstlc lstnm lstdt lsttm compnum basedsn compdsn section label type;
  run;

  /* transpose the data in order to do some checks and create a summary report */
  /* 20170320 - richann - add compnum to transpose to avoid duplicates */
  /*                      if more than one PROC COMPARE in output      */
  /* 20170629 - richann - need to include the compare location and the compare counter */
  proc transpose data = alllsts
                  out = talllsts (drop = _:);
    var value;
    id type;
    by lstlc lstnm lstdt lsttm compnum basedsn compdsn section label;
  run;

  /* need to determine if certain variables exist */
  data _null_;
    dsid = open("talllsts");
    call symputx('confexst', varnum(dsid, 'Conflict'));
    call symputx('vreqexst', varnum(dsid, 'AllVarEq'));
    call symputx('vrneexst', varnum(dsid, 'SomeVarNE'));
    call symputx('vlneexst', varnum(dsid, 'ValNE'));
    /* 20170629 - richann - check for variable that checks for not exactly equal */
    call symputx('vneeexst', varnum(dsid, 'ValNEE'));
    rc = close(dsid);

    /* 20170629 - richann - add Variables with Unequal Values and Vars with Different Attrib */
     /*                      to list of variables to check for existence                      */    
    dsid = open("alluv");
    call symputx('vvneexst', varnum(dsid, 'VarValNE'));
    call symputx('dfatexst', varnum(dsid, 'DiffAttr'));
    rc = close(dsid);
  run;

  /* 20170320 - richann - need to incorporate PROC COMPARE number to keep a record for each */
  /* 20170629 - richann - change name of data set from 'report' to 'report_1' due to updates*/
  /*                      for the incorporation of Vars with Unequal Values portion         */
  /*                      made various changes in data step to allow for not exactly equal  */
  data report_1 (keep = lstlc lstnm lstdt lsttm basedsn compdsn message compnum);
    set talllsts;
   by lstnm lstdt lsttm compnum basedsn compdsn section label;

   length lblmsg varmsg1 varmsg2 varmsg3 varmsg4 
           obsmsg1 obsmsg2 obsmsg3 obsmsg4 obsmsg5 obsmsg6
           aeqmsg dupmsg1 dupmsg2 cnfmsg valmsg1 valmsg2 valmsg3 valmsg4 $200;
   retain lblmsg varmsg1 varmsg2 varmsg3 varmsg4 
           obsmsg1 obsmsg2 obsmsg3 obsmsg4 obsmsg5 obsmsg6
           aeqmsg dupmsg1 dupmsg2 cnfmsg valmsg1 valmsg2 valmsg3 valmsg4;
   if first.compdsn then do;
        lblmsg = '';
       varmsg1 = '';
       varmsg2 = '';
       varmsg3 = '';
       varmsg4 = '';
       obsmsg1 = '';
       obsmsg2 = '';
       obsmsg3 = '';
       obsmsg4 = '';
       obsmsg5 = '';
       obsmsg6 = '';
       aeqmsg = '';
       dupmsg1 = '';
       dupmsg2 = '';
       cnfmsg = '';
       valmsg1 = '';
       valmsg2 = '';
       valmsg3 = '';
       valmsg4 = '';
   end;

   /* for SDTM and ADaM data sets only see if the data set labels match */
   /* and see if number of variables match - checking number of vars is */
   /* not necessary for TLFs because there may be extra vars in DEV due */
   /* to standard table macros                                          */
   /* 20170629 - richann - need to check labels and number of vars regardless   */
   /*                      original code about 'SD_', 'AD_' were client specific*/
   if /*index(upcase(lstnm), 'SD_') or index(upcase(lstnm), 'AD_')*/ section = 'Data Set Summary' then do;
     dsn = /*substr(lstnm, (index(lstnm, 'SD_') or index(lstnm, 'AD_')) + 3)*/lstnm;
     if label = 'DSLbl' and base ne '' and comp ne '' and base ne comp then 
         lblmsg = catx(" ", "Data set label between DEV and VER for", dsn, 
                      "do not match. Label for DEV =", base, "Label for VER =", comp);


     if label = 'NumVar' and base ne '' and comp ne '' and common ne '' then do;
       if base ne comp then varmsg1 = catx(" ", "Number of vars between DEV and VER for", dsn, 
                                            "do not match. Number of vars for DEV =", base, 
                                            "Number of vars VER =", comp);
       else varmsg1 = '';
       if base ne common then varmsg2 = catx(" ", "Number of vars in common (", common, 
                                              ") between DEV and VER do not match number of vars in DEV.");
      else varmsg2 = '';
     end; /* end label = 'NumVar' and base ne '' ...*/
      
      /* determine if there are variables in one data set but not the other */
     if label = 'VarsIn' then do;
       if base ne '' then varmsg3 = catx(" ", "There are", base, "vars in", basedsn, "that are not in", compdsn);
       else varmsg3 = '';
       if comp ne '' then varmsg4 = catx(" ", "There are", comp, "vars in", compdsn, "that are not in", basedsn);
       else varmsg4 = '';
     end; /* end label = 'VarsIn' */
   end; /* end section = 'Data Set Summary' */

   /* determine if the number of observations between DEV and VER match */
   if label = 'NumObs' and base ne '' and comp ne '' and common ne '' then do;
     if base ne comp then obsmsg1 = catx(" ", "In Data Set Summary Section, number of obs between DEV and VER for", dsn, 
                                          "do not match. Number of obs for DEV =", base, 
                                          "Number of obs VER =", comp);
     else obsmsg1 = '';
     if base ne common then obsmsg2 = catx(" ", "Number of obs in common (", common, 
                                              ") between DEV and VER found in Observation Summary Section do not match number of obs in DEV found in Data Set Summary Section.");
     else obsmsg2 = '';
   end; /* end label = 'NumObs' ... */

   /* determine if the number of observations read for DEV and VER match the number of observations in common */
   if label = 'ObsRead' and base ne '' and comp ne '' and common ne '' then do;
     if base ne comp then obsmsg3 = catx(" ", "In Observation Summary Section, number of observations read for DEV does not match number of obs read for VER", dsn, 
                                          "Number of obs read for", basedsn, "=", base, 
                                          "Number of obs read for", compdsn, "=", comp);
     else obsmsg3 = '';
     if base ne common then obsmsg4 = catx(" ", "In Observation Summary Section, number of obs in common (", common, 
                                              ") between DEV and VER do not match number of obs read for DEV (", base, ").");
     else obsmsg4 = '';
   end; /* end label = 'ObsRead' ... */
      
    /* determine if there are observations in one data set but not the other */
   if label = 'ObsIn' then do;
     if base ne '' then obsmsg5 = catx(" ", "There are", base, "obs in", basedsn, "that are not in", compdsn);
     else obsmsg5 = '';
     if comp ne '' then obsmsg6 = catx(" ", "There are", comp, "obs in", compdsn, "that are not in", basedsn);
     else obsmsg6 = '';
   end; /* end label = 'ObsIn' */

   if label = 'AllEq' and (obsvareq ne 'Y' or obsvarne ne '0') then 
       aeqmsg = catx(" ", "Some values are not equal for variables and observations checked:", obsvarne);

   if label = 'DupObs' then do;
     if base ne '' then dupmsg1 = catx(" ", "There are", base, "duplicate observations in", basedsn);
     else dupmsg1 = '';
     if comp ne '' then dupmsg2 = catx(" ", "There are", comp, "duplicate observations in", compdsn);
     else dupmsg2 = '';
   end; /* end label = 'DupObs' */

   /* these will only execute if there are issues and the PROC COMPARE has unequal values */
   %if &confexst ne 0 %then %do;
      if label = 'ConfType' then cnfmsg = catx(" ", "There are", conflict, "variables with conflicting data types");
   %end;

   %if &vreqexst ne 0 %then %do;
     if label = 'NumVarVal' and allvareq ne . then valmsg1 = catx(" ", "Number of Variables Compared with All Observations Equal: ", allvareq);
   %end;

   %if &vrneexst ne 0 %then %do;
     if label = 'NumVarVal' and somevarne ne . then valmsg2 = catx(" ", "Number of Variables Compared with Some Observations Unequal: ", somevarne);
   %end;

   %if &vlneexst ne 0 %then %do;
     if label = 'NumVarVal' and valne ne . then valmsg3 = catx(" ", "Total Number of Values with Compare Unequal: ", valne);
   %end;

   %if &vneeexst ne 0 %then %do;
     if label = 'NumVarVal' and valnee ne . then valmsg4 = catx(" ", "Total Number of Values not EXACTLY Equal:  ", valnee);
   %end;

   /* 20170320 - richann - want to keep a record for each PROC COMPARE number */
   if last./*compdsn*/compnum then do;
     length message $200;
     /* if there are no messages (with exception of duplicates) */
     /* then create a message indicate all matched              */
     /* still need to output duplicate message see array        */
     if cmiss(lblmsg, varmsg1, varmsg2, varmsg3, varmsg4, 
               obsmsg1, obsmsg2, obsmsg3, obsmsg4, obsmsg5, obsmsg6,
               aeqmsg, cnfmsg, valmsg1, valmsg2, valmsg3, valmsg4) = /*16*/17 then do;
      message = catx(" ", basedsn, "and", compdsn, "match.");
       output;
      end; /* end cmiss( ... */

      /* create a record for each message so it can be looked into */
     array msg(*) lblmsg varmsg1 varmsg2 varmsg3 varmsg4 
                   obsmsg1 obsmsg2 obsmsg3 obsmsg4 obsmsg5 obsmsg6
                   aeqmsg dupmsg1 dupmsg2 cnfmsg valmsg1 valmsg2 valmsg3 valmsg4;
     do i = 1 to dim(msg);
       if msg(i) ne '' then do;
         message = msg(i);
         output;
       end; /* end msg(i) */
     end /* end do i = 1 to dim(msg) */;
   end; /* end last.compdsn */
  run;

  /* 20170629 - richann - need to create a comp message of the variables with unequal values */
  %if &vvneexst ne 0 %then %do;
    data report_2;
     set alluv;
      where label = 'VarValNE';
      length message $200;
      message = catx(" ", "Variable with Unequal Values: ", varvalne);
   run;
  %end;

  /* 20170629 - richann - need to create a comp message of the variables with different attributes */
  %if &dfatexst ne 0 %then %do;
    data report_3;
     set alluv;
      where label = 'DiffAttr';
      length message $200;
      message = catx(" ", "Common Variable with Different Attributes: ", diffattr);
   run;
  %end;

  /* 20170629 - richann - combine the all reports into one final report */
  data report;
    set report_:;
  run;

  /* if the name of the output file is not specified then default to the name */
  %if &out =  %then %do;
    %let out=all_checkcmps;
  %end;

  /* if the location of the output file is not specified then default to the search location */
  %if "&loc2" = "" %then %do;
    data _null_;
     call symputx("loc2", "&dloc");
   run;
  %end;

  /* 20170629 - richann need to sort the data set */
  proc sort data = report presorted;
    by lstlc lstnm;
  run;

  /* create the report */
  ods listing close;
  options orientation=landscape missing = '';

  ods rtf file="&loc2.&slash.&out..rtf";

  /* 20170320 - richann - add title and footnote */
  title "Summary of PROC COMPARE Results";
  footnote "* If there are multiple PROC COMPARE outputs, the number distinguishes between the different PROC COMPARE results in the output.";

  /* 20170626 - richann - print by compare file location and add line number */
  proc report data=report ls=140 ps=43 spacing=1 missing nowindows headline;
    by lstlc;
   column lstnm lstdt lsttm compnum basedsn compdsn message; 
   define lstnm   / order   style(column)=[width=12%]      "Lst Name"; 
   define lstdt   / order   style(column)=[width=10%]      "Lst Date"; 
   define lsttm   / order   style(column)=[width=10%]      "Lst Time"; 
   define compnum / order   style(column)=[width=12%]      "PROC COMPARE Number*";
   define basedsn / order   style(column)=[width=12%]      "BASE Data Set";
   define compdsn / order   style(column)=[width=12%]      "COMPARE Data Set";
   define message / display style(column)=[width=30%] flow "PROC COMPARE Message";

   /* force a blank line after each file */
   compute after lstnm;
     line " ";
   endcomp;
  run; 

  ods rtf close;
  ods listing;
%mend checkcmps;
