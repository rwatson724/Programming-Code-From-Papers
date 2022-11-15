/****************************************************************************************
Program:          runfreq.sas
Protocol:         Study A
SAS Version:      9.4
Developer:        Richann Watson 
Date:             26JUL2017 
Purpose:          Obtain frequency counts, determine appropriate test statistic (Chi-Square or Fisher Exact). 
Operating Sys:    Windows 7
Macros:           NONE
Input:            Input Data Set for Processing
Output:           Temporary Data Sets to use for Final Output
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
----------------------------------------------------------------------------------------- 
****************************************************************************************/
%macro runfreq(indsn  = ,    /* input data set - include libname (i.e., adam.adeff) */
               sortby = ,    /* sort data - if need to sort descending specify      */
               whrcls = ,    /* (opt'l) where clause used to subset input data set  */
			                    /* note that data should already be one record per subj*/
                             /* or where clause will get it to one record per subj  */
               kpvars = ,    /* (opt'l) variables to keep if not specified will be  */
                             /* determined based on the sortby                      */
               tbvars = ,    /* (opt'l) table statment if not specified will be     */
                             /* determined based on the sortby                      */
               grpvar = ,    /* (opt'l) treatment / group variable (i.e., variable  */
                             /* that p-value will be for) - if not specified will   */
                             /* be determined by the sortby                         */
               expcnt = 5,   /* (opt'l) minimum expected counts for each cell used  */
                             /* for determining if Chi-Sqr or Fisher Exact is used  */
               fshchi = 0.25,/* (opt'l) threshold used to determine whether Chi-Sqr */
                             /* or Fisher Exact p-value will be used                */
               plttwo = ,    /* (opt'l) option for a twoway plot, if want 2-way plot*/
                             /* specify GROUPVERTICAL, GROUPHORIZONTAL or STACKED   */
               catrnd = Y,   /* (opt'l) if Cochran-Armitage trend test is needed    */
               bimain = ,    /* (opt'l) if two group comparison and/or proportional */
                             /* Binomial CI is needed then specify main trtm/grp or */
                             /* that others will be compared against-embed in quotes*/
               bicomp =      /* (opt'l) if two group comparison and/or proportional */
                             /* Binomial CI is needed then specify all comparator   */
                             /* treatments / groups - embed each group in quotes    */
                             /* separated by a exclamation mark (!)                 */
			  );

   /* delete all temp data sets to avoid using incorrect data sets */
   proc datasets library = work nolist memtype = data kill;
   quit;

   /* need to determine keep and table variables if they are not specified */
   data _null_;
      keepvar = tranwrd(upcase("&sortby"), 'DESCENDING', '');
      /*if index(upcase("&sortby"), 'DESCENDING') 
         then tablvar =   tranwrd(upcase("&sortby"), 'DESCENDING', '*');
      else*/tablvar = tranwrd(compbl(keepvar), ' ', '*');

      if first(compress(tablvar)) = '*' then tablvar = substr(tablvar, 2);
	  if first(reverse(compress(tablvar))) = '*' then 
         tablvar = reverse(substr(reverse(compress(tablvar)), 2));


      %if "&kpvars" = "" %then call symputx('kpvars', keepvar);; 
      %if "&tbvars" = "" %then call symputx('tbvars', tablvar);;
      %if "&grpvar" = "" %then call symputx('grpvar', scan(tablvar, 1));;

      x = count(resolve('&tbvars'), '*');

      /* create a variable that will be used to determine individual group variable */
      do i = 1 to x;
        y = i + 1;
        call symputx(cats('grpvar', put(y, 3.)), scan(resolve('&tbvars'), y, '*'));
      end;

      /* count number of variables so the correct value for _TYPE_ can be specified */
      /* since macro variable tbvars is being assigned w/n the data step we need to */
      /* use resolve function so that while being constructed it does not resolve it*/
      /* but will resolve during the data step execution                            */
      call symputx('type', repeat('1', x));

      /* number of group variables on the table statement */
      call symputx('numvars', x + 1);
   run;

   /* so only need to sort once - sort by variables needed for binomial proportion */
   /* i.e., if need comparator group (B) - main group (A) and response (Y) - no    */
   /* response (N) - sort descending group descending response                     */
   proc sort data=&indsn 
             out=outdsn (keep = &kpvars);
     by &sortby;
     where &whrcls;
   run;

   /* note that for cochran-armitage trend test we are looking for dose response */
   /* (i.e., did response increase / decrease based on the dose)                 */
   /* so need to look at the one sided p-value                                   */
   /* obtain counts for each treatment / group by response (i.e., _TYPE_='11')   */
   /* if treatment / group is first variable in tables statement & overall counts*/
   /* by treatment / group is needed then use records where _TYPE_='10' and use  */
   /* RowPercent for percentages for each response within a treatment / group    */
   /* if treatment / group is 2nd variable in tables statement & overall counts  */
   /* by treatment / group is needed then use records where _TYPE_='01' and use  */
   /* ColPercent for percentages for each response within a treatment / group    */
   ods output crosstabfreqs = ctf (where = (_TYPE_ ne '00')
                                   drop = Table _TABLE_ Missing Percent);
   ods output chisq = chi_oall;
   ods output fishersexact = fis_oall;
   /* need to semicolon one to end %if and one to end ods statement */
   %if &catrnd = Y %then ods output trendtest = trend; ; 
   proc freq data = outdsn order = data;
      tables &tbvars / OUTPCT chisq cmh fisher expected  
                       %if &plttwo ne  %then plots=freqplot(twoway=&plttwo);
                       %if &catrnd = Y %then trend;
          ; /* this semicolon ends the tables statement - do NOT delete */
   run;

   /* count the number of expected cells < number specific and divide total */
   /* number of cells to determine if need to use Chi-Square or Fisher test */ 
   data _null_;
      set ctf (where=(_TYPE_ = "&type")) end=eof;

      retain numcell numcelllt5;
      if _n_ = 1 then do;
         numcell = 0;
         numcelllt5 = 0;
      end;
      numcell + 1;
      if expected < &expcnt then numcelllt5 = numcelllt5 + 1;

      /* determine if a Chi-Square or Fisher test should be performed */
      /* Note keep one record per treatment in odd case they want to  */
      /* do tests by treatment instead of overall                     */
      if eof then do;
         if numcelllt5 / numcell > &fshchi then test = 'FIS';
         else test = 'CHI';
         call symputx ('test', test);
      end;
   run;

   /* if binomial proportions are needed then loop through each comparator group */
   /* will also retrieve Chi-Sqr / Fisher Exact p-value for each comparison      */
   /* can only do pairwise and bici if there are only two variables              */
   %if &bimain ne   and &numvars = 2 %then %do;
      %let nobici = 0;
      %let x = 1;
      %let bigrp = %scan(&bicomp, &x, '!');
      %do %while ("&bigrp" ne "");

         /* determine the number of levels for each var to see if bici can be done */
         proc sql noprint;
            select count(distinct &grpvar2) into :nvar2_&x
            from ctf
            where &grpvar in (&bimain "&bigrp");
         quit;

         ods output chisq = chi_&x;
         ods output fishersexact = fis_&x;
         proc freq data = ctf order = data;
            where _TYPE_ = '11';
            weight FREQUENCY;
            tables &tbvars / %if &&nvar2_&x = 2 %then binomial; 
                             alpha=0.05 chisq fisher;
            /* only execute binomial proportion CI if data is 2x2 */
            %if &&nvar2_&x = 2 and &numvars = 2 %then %do;
               exact riskdiff;
               output out=bci_&x (keep = L_RDIF1 U_RDIF1) riskdiff;
            %end;
            where also &grpvar in (&bimain "&bigrp");
         run;

         /* if any one of the outputs can’t be produced don’t produce any of bici */
         %if &&nvar2_&x > 2 %then %let nobici = 1;;

         %let x = %eval(&x + 1);
         %let bigrp = %scan(&bicomp, &x, '!');
      %end;

      /* only produce bici if each group variable has at most 2 levels  */
      /* only produce bici if there are only two variables on table stmt*/
      /* otherwise produce a message to the log                         */
      %if &nobici ^= 1 and &numvars = 2 %then %do;
         data bici;
            set bci_: indsname= inputdsn;
            length &grpvar.n $8 bici $20;
            /* only want number or 'OALL' portion */
            &grpvar.n = scan(scan(inputdsn, 2), 2, '_');
            /* need to convert values to percentages */
            bici = cats('(', catx(', ', put(L_RDIF1 * 100, 8.1), 
                                        put(U_RDIF1 * 100, 8.1)), ')');
         run;
      %end;
      %else %do;
         %put %sysfunc(COMPRESS(W ARNING:)) data needs to be 2x2 to do BiCi - at least one variable has more than 2 levels or there are more than two variables;
      %end;
   %end;   

   /* combine the test statistics into one to determine what is needed later */
   data t_pvals (keep=test &grpvar.n tvalue pvalue %if &numvars > 2 %then table;);
      set &test._: (where = (%if &test = CHI %then statistic = 'Chi-Square';
                             %else name1 = 'XP2_FISH';))
                    indsname = inputdsn;
      length &grpvar.n pvalue tvalue $8;
      test = "&test";
	  /* only want number or 'OALL' portion */
	  &grpvar.n = scan(scan(inputdsn, 2), 2, '_');
	
      %if &test = CHI %then %do;
         tvalue = put(value, 8.2);
         pvalue = put(prob, 8.3);
      %end;
      %else %do;
         tvalue = put(nValue1, 8.2);
         pvalue = put(cValue1, 8.3);
      %end;
   run;

%mend runfreq;
