/****************************************************************************************
Program:          checklogs.sas
Protocol:         Study A
SAS Version:      9.4
Developer:        Richann Watson 
Date:             05MAY2016 
Purpose:          Check the log of an individual file or to check the logs in a directory. 
Operating Sys:    Windows 7
Macros:           NONE
Input:            log files
Output:           Log Report
Validation Ready: N/A
Validated by:
Date Validated:
Comments:
----------------------------------------------------------------------------------------- 

Revision History:
Date: 08JUL2016
Requestor: Maintenance
Modification: Modifications throughout to allow for execution in either Windows or Unix.
Modifier: Richann Watson

Date: 25OCT2016       
Requestor: User
Modification: Need to allow for writing report to another location. Added loc2 parameter.
Modifier: Richann Watson

Date: 04JAN2017
Requestor: Maintenance
Modification: Added code to end if environment not defined.
              Added a default delimiter parameter to allow for spaces in filename.
              Made necessary modifications to allow for delimiter in fnm parameter.
Modifier: Richann Watson

Date: 10JAN2017
Requestor: Maintenance
Modification: Moved creation of flog within conditional if statement.
Modifier: Richann Watson

Date: 06JUN2017 & 26JUN2017
Requestor: Maintenance
Modification: Allow for logs to be stored in multiple locations.
              Allow for either spreadsheet of unwanted log message and/or default messages.
              Incorporate the log line number into the report
Modifier: Richann Watson

Date: 08AUG2017
Requestor: Maintenance
Modification: Check for exist of a folder and if didn't exist then skip and go to next folder.
Modifier: Richann Watson

Date: 16NOV2018
Requestor: Maintenance
Modification: Change 'abort abend' to '%abort'.
Modifier: Richann Watson
----------------------------------------------------------------------------------------- 
****************************************************************************************/

/* retrieve all the logs in the specified directory */
%macro checklogs(loc=,  /* location of where the log files are stored       */
                        /* can add multiple locations but they need to be   */
                        /* separated by the default delimiter '@' or the    */
                        /* user specified delimiter                         */
                 loc2=, /* location of where report is stored (optional)    */
                 fnm=,  /* which types of files to look at (optional)       */
                        /* e.g., Tables – t_, Figures – f_, Listings – l_   */ 
                        /* separate types of files by delimiter indicated in*/
                        /* the delm macro parameter (e.g., t_@f_)           */
                 delm=@,/* delimiter used to separate types of files (opt'l)*/
                 msgf=, /* FULL file name (includes location) of spreadsheet*/
                        /* where the user specified log messages are stored */
                 msgs=, /* sheet/tab name in spreadsheet that contains the  */
                        /* unwanted log messages default to 'Sheet1' (opt'l)*/
                 msgv=, /* name of column in spreadsheet (convert spaces to */
                        /* underscores - must be specified if file specified*/
                        /* (conditionally required)                         */
                 out=   /* log report name (optional)                       */);

             
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
  %if "&fnm" ne "" %then %do;  /* begin conditional if "&fnm" ne "" */
    data _null_;
      length fullwhr $2000.;
      retain fullwhr;

      /* read in each log file and check for undesired messages */
      %let f = 1;
      %let typ = %scan(&fnm, &f, "&delm");

      /* loop through each type of filename to build the where clause */
      /* embed &typ in double quotes in case filename has special characters/spaces */
      %do %while ("&typ" ne "");  /* begin do while ("&typ" ne "") */

        partwhr = catt("index(flog, '", "&typ", "')");
        fullwhr = catx(" or ", fullwhr, partwhr);

        call symputx('fullwhr', fullwhr);

        %let f = %eval(&f + 1);
        %let typ = %scan(&fnm, &f, "&delm");
      %end;  /* end do while ("&typ" ne "") */

    run;
  %end;  /* end conditional if "&fnm" ne "" */

  /* if a spreadsheet is provided with unwanted log messages */
  /* then need to use that to build search criteria to be    */
  /* used later in the program                               */
  %let fullmsg = "";
  %if "&msgf" ne "" %then %do;  /* begin conditional if "&msgf" ne "" */
    libname logmsg xlsx "&msgf";

    /* need to make sure spreadsheet exists if it is specified */
    %if %sysfunc(fileexist(&msgf)) = 1 %then %do;  /* begin conditional if 
                                                      %sysfunc(filexist(&msgf) = 1 */

      data _null_;
        length fullmsg1 fullmsg2 fullmsg3 $2000;
        retain fullmsg1 fullmsg2 fullmsg3;
        set %if "&msgs" ne "" %then logmsg."&msgs"n;
            %else logmsg."Sheet1"n;
            end = eof; /* need this semicolon to end the set statement */

        partmsg = catt('index(upcase(line), "', (upcase(&msgv)), '")');

        if length(fullmsg1) + length(partmsg) <= 2000 then 
             fullmsg1 = catx(" or ", fullmsg1, partmsg);
        else if length(fullmsg2) + length(partmsg) <= 2000 then 
             fullmsg2 = catx(" or ", fullmsg2, partmsg);
        else fullmsg3 = catx(" or ", fullmsg3, partmsg);

        if eof then do;
             call symputx('fullmsg1', fullmsg1);
           if fullmsg2 ne '' then call symputx('fullmsg2', fullmsg2);
           if fullmsg3 ne '' then call symputx('fullmsg3', fullmsg3);
        end;
      run;
    %end;  /* end conditional if %sysfunc(fileexist(&msgf)) = 1 */

    libname logmsg clear;
  %end;  /* end conditional if "&msgf" ne "" */

  /* need to make sure alllogs does not exist before start processing */
  proc datasets;
    delete alllogs;
  quit;

  /* need to process each location for logs separately */
  %let g = 1;
  %let lcn1 = %scan(&loc, &g, "&delm");

  /* attempt to create a libname for each location specified */
  %do %while ("&&lcn&g" ne "");
    %let g = %eval(&g + 1);
    %let lcn&g = %scan(&loc, &g, "&delm");
  %end;

  /* initialize the location that will act as a place holder till the end of the program */
  %let dloc=;

  /* loop through each directory specified */
  %do k = 1 %to %eval(&g - 1);  /* begin do i = 1 to %eval(&g - 1) */

      /* need to make sure the location exists so create a temp library */
      libname templib&k "&&lcn&k";

      /* begin looking through each log location for specified log types */
      /* if &SYSLIBRC returns a 0 then path exists                       */
      %if &syslibrc = 0 %then %do;  /* begin if &syslibrc = 0 */

        /* create a default location for report if report location not specified */
        /* only create default location for first location that exists           */
        %if "&dloc" = "" %then %do;
           %let dloc = &&lcn&k; 
       %end;

       /* need to build pipe directory statement as a macro var  */
       /* because the statement requires a series of single and  */
       /* double quotes - by building the directory statement    */
       /* this allows the user to determine the directory rather */
       /* than it being hardcoded into the program               */
       /* macro var will be of the form:'dir "directory path" '  */
       data _null_;
         libnm = "&&lcn&k";
         dirnm = catx(" ", "'", "&ppcmd", quote(libnm), "'");
         call symputx('dirnm', dirnm);
       run;

       /* read in the contents of the directory containing the logs */
       filename pdir pipe &dirnm lrecl=32727;

       data logs&k (keep = flog fdat ftim filename numtok);
         infile pdir truncover scanover;
         input filename $char1000.;

         length flog $50 fdat ftim $10;

         /* keep only the logs */
         if index(filename, ".log");

         /* count the number of tokens (i.e., different parts of filename) */
         /* if there are no spaces then there should be 5 tokens           */
         numtok = countw(filename,' ','q');

         /* parse out the string to get the log name */
         /* note on the scan function a negative #   */
         /* scans from the right and a positive #    */
         /* scans from the left                      */
         /* for log keep only first part (e.g. 'ae') */
         /* need to build the flog value based on number of tokens */
         /* if there are spaces in the log name then need to grab  */
         /* each piece of the log name                             */
         /* the first token that is retrieved will have '.log' and */
         /* it needs to be removed by substituting a blank         */
         /* need to do within conditional if statements since num  */
         /* of tokens for Windows is different than Unix           */ 
         *flog = scan(scan(filename, -1, " "), 1);

         /* entire section below allows for either Windows or Unix */
         /*********** WINDOWS ENVIRONMENT ************/
         /* the pipe will read in the information in */
         /* the format of: date time am/pm size file */
         /* e.g. 08/24/2015 09:08 PM 18,498 ae.log   */
         /*    '08/24/2015' is first token from left */
         /*    'ae.log' is first token from right    */
         %if &sysscp = WIN %then %do;  /* begin conditional if &sysscp = WIN */
           do j = 5 to numtok;
             tlog = tranwrd(scan(filename, 4 - j, " "),  ".log", "");
             flog = catx(" ", tlog, flog);
           end;
           ftim = catx(" ", scan(filename, 2, " "), scan(filename, 3, " "));
           fdat = put(input(scan(filename, 1, " "), mmddyy10.), date9.);
         %end;  /* end conditional if &sysscp = WIN */
         
         /*************************** UNIX ENVIRONMENT ****************************/
         /* the pipe will read in information in the format of: permissions, user,*/
         /* system environment, file size, month, day, year or time, filename     */
         /* e.g. -rw-rw-r-- 1 userid sysenviron 42,341 Oct 22 2015 ad_adaapasi.log*/
         /*    '-rw-rw-r--' is first token from left                              */
         /*    'ad_adaapasi.log' is first token from right                        */
         %else %if &sysscp = LIN X64 %then %do;  /* begin conditional if 
                                                    &sysscp = LIN X64 */
    
           do j = 9 to numtok;
             tlog = tranwrd(scan(filename, 8 - j, " "),  ".log", "");
             flog = catx(" ", tlog, flog);
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

       /* create a list of logs, dates, times and store in macro variables */
       /* count number of logs in the specified folder and retain in macro variable */
       proc sql noprint;
         select flog,
                fdat, 
                ftim,
                count (distinct flog)
                into : currlogs separated by "&delm",
                     : currdats separated by " ",
                     : currtims separated by "@",
                     : cntlogs
         from logs&k
         %if "&fnm" ne "" %then where &fullwhr;  
           ; /* need to keep extra semicolon */ 
       quit;

       /* only loop thru the directory if the number of logs found is greater than 0 */
       %if &cntlogs ne 0 %then %do;  /* begin conditional if &cntlogs ne 0 */

         /* read in each log file and check for undesired messages */
         %let x = 1;
         %let lg = %scan(&currlogs, &x, "&delm");
         %let dt = %scan(&currdats, &x);
         %let tm = %scan(&currtims, &x, '@');

         /* loop thru each log in the directory and look for undesirable messages */
         /* embed &lg in double quotes in case filename has special characters/spaces */
         %do %while ("&lg" ne "");  /* begin do while ("&lg" ne "") */
           /* read the log file into a SAS data set to parse the text */ 
           data logck&k&x;
             infile "&&lcn&k.&slash.&lg..log" truncover pad;

             /* use $char1000 in order to maintain spacing to get correct line number */
             input line $char1000.;

             /* need to retain the line number so that when a message is encountered */
             /* then will know hwere in log to find it                               */
             retain lineno;

             if _n_ = 1 then lineno = .;
             if anydigit(line) = 1 then 
                lineno = input(substr(line, 1, notdigit(line)-1),best.);

             /* keep only the records that had an undesirable message */
             if index(upcase(line), "WARNING") or
                index(upcase(line), "ERROR") or
                index(upcase(line), "UNINITIALIZED") or
                index(upcase(line), "NOTE: MERGE") or
                index(upcase(line), "MORE THAN ONE DATA SET WITH REPEATS OF BY") or
                index(upcase(line), "VALUES HAVE BEEN CONVERTED") or
                index(upcase(line), "MISSING VALUES WERE GENERATED AS A RESULT") or
                index(upcase(line), "INVALID DATA") or
                index(upcase(line), "INVALID NUMERIC DATA") or
                index(upcase(line), "AT LEAST ONE W.D FORMAT TOO SMALL")
                /* allow for user specific messages to be stored in a spreadsheet */
                %if %symexist(fullmsg1) %then or &fullmsg1;
                %if %symexist(fullmsg2) %then or &fullmsg2;
                %if %symexist(fullmsg3) %then or &fullmsg3;
                ; /* need extra semicolon to end if statement */

             /* create variables that will contain the log that is being scanned */
             /* as well as the and date and time that the log file was created   */
             length lognm $25. logdt logtm $10. loglc $200.;
             lognm = upcase("&lg");
             logdt = "&dt";
             logtm = "&tm";

             /* create a dummy variable to create a column on report that will allow */
             /* users to enter a reason if the message is allowed                    */
             logrs = ' ';

             /* need to create a variable that captures the location */
             /* in case there are multiple log locations - need to be*/
             /* print the report by log location                     */
             /* nolog will be used to flag the directories with no   */
             /* logs found                                           */
             loglc = "&&lcn&k";
             label loglc = 'Log Location';
             nolog = .;
           run;

           /* because there are sometimes issues with SAS certificate */
           /* there will be warnings in the logs that are expected    */
           /* these need to be removed                                */
           data logck&k&x._2;
             set logck&k&x.;
             if index(upcase(line), 'UNABLE TO COPY SASUSER') or
                index(upcase(line), 'BASE PRODUCT PRODUCT') or
                index(upcase(line), 'EXPIRE WITHIN') or
                (index(upcase(line), 'BASE SAS SOFTWARE') and 
                 index(upcase(line), 'EXPIRING SOON')) or
                index(upcase(line), 'UPCOMING EXPIRATION') or
                index(upcase(line), 'SCHEDULED TO EXPIRE') or
                index(upcase(line), 'SETINIT TO OBTAIN MORE INFO') then delete;
           run;

           /* determine the number of undesired messages were in the log */
           data _null_;
            if 0 then set logck&k&x._2 nobs=final;
             call symputx('numobs',left(put(final, 8.)));
           run;

           /* if no undesired messages in log create a dummy record for report */
           %if &numobs = 0 %then %do;  /* begin conditional if &numobs = 0 */
             data logck&k&x._2;
               length lognm $25. line $1000. logdt logtm $10. loglc $200.;
               line = "No undesired messages.  Log is clean.";
               lognm = upcase("&lg");
               logdt = "&dt";
               logtm = "&tm";

               /* create a dummy variable to create a column on the report that */
               /* allow users to enter a reason if the message is allowed       */
               logrs = ' '; 

               /* adding variables for line number and log location */
               /* nolog will be used to flag the directories with   */
               /* no logs found                                     */
               lineno = .;
               loglc = "&&lcn&k";
               label loglc = 'Log Location';
               nolog = .;
               output;
             run;
           %end;  /* end conditional if &numobs = 0 */

           /* append all the results into one data set */
           /* need to check to see if data set exists-during 1st iteration it should */
           /* not exist because it was deleted at top of program                     */
           %let exist = %sysfunc(exist(alllogs));

           %if /*&x = 1*/ &exist = 0 %then %do;
             data alllogs;
               set logck&k&x._2;
             run;
           %end;
           %else %do;
             proc append base=alllogs
                         new=logck&k&x._2;
             run;
           %end;

           %let x = %eval(&x + 1);
           %let lg = %scan(&currlogs, &x, "&delm");
           %let dt = %scan(&currdats, &x);
           %let tm = %scan(&currtims, &x, '@');
         %end;  /* end do while ("&lg" ne "") */

       %end;  /* end conditional if &cntlogs ne 0 */

       %else %do;
         data nolog&k;
           length lognm $25. line $1000. logdt logtm $10. loglc $200.;
           line = '';
           lognm = '';
           logdt = '';
           logtm = '';
           logrs = ''; 
           lineno = .;
           loglc = "&&lcn&k";
           label loglc = 'Log Location';
           nolog = 1;
           output;
         run;       

         %let exist = %sysfunc(exist(alllogs));

         %if &exist = 0 %then %do;
           data alllogs;
             set nolog&k;
           run;
         %end;
         %else %do;
           proc append base=alllogs
                       new=nolog&k;
           run;
         %end;
       %end;
     %end;  /* end if &syslibrc = 0 */

     %else %do;
       %put %sysfunc(compress(W ARNING:)) "directory &&lcn&k does not exist";
     %end;

  %end;  /* begin do i = 1 to %eval(&g - 1) */

  /* if the name of the output file is not specified then default to the name */
  %if "&out" =  "" %then %do;
    %let out=all_checklogs;
  %end;

  /* if the name of the output file is not specified then default to the name */
  %if "&loc2" = "" %then %do;
    data _null_;
      call symputx("loc2", "&dloc");
    run;
  %end;

  %let exist = %sysfunc(exist(alllogs));
  %if &exist ne 0 %then %do;
     /* since a list of files can be provided then the files may not be in order */
     proc sort data=alllogs presorted;
       by lognm line;
     run;

     /* sort the final report by location */
     proc sort data = alllogs;
       by loglc nolog lognm lineno;
     run;

     /* create the report */
     ods listing close;
     options orientation=landscape missing='';

     ods rtf file="&loc2.&slash.&out..rtf";
     title "Summary of Log Issues";

     /* nolog will determine if message about no */
     /* logs found in directory will be printed  */
     proc report data=alllogs ls=140 ps=43 spacing=1 missing nowindows headline;
       by loglc;
       column nolog lognm logdt logtm lineno line logrs; 
       define nolog / analysis sum noprint;
       define lognm / order   style(column)=[width=12%]      "Log Name"; 
       define logdt / display style(column)=[width=12%]      "Log Date"; 
       define logtm / display style(column)=[width=12%]      "Log Time"; 
       define lineno/ display style(column)=[width=12%]      "Line Number";
       define line  / display style(column)=[width=30%] flow "Log Message";
       define logrs / display style(column)=[width=20%] flow "Reason Message is Allowed";

       /* force a blank line after each file */
       compute after lognm;
         line " ";
       endcomp;

       /* if there are no logs in the directory then display message indicating that */
       /* do this to verify that the directory was indeed checked and not overlooked */
       compute after _page_;
         if nolog.sum ^= . then addnote='There are no log files found in the directory';
         line @20 addnote $50.;
       endcomp;
     run; 

     ods rtf close;
     ods listing;
  %end;
  %else %do;      
     %put %sysfunc(compress(W ARNING:)) "None of the log locations specified exist";
  %end;
%mend checklogs;

