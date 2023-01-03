/****************************************************************************************
Program:          domixed.sas
Protocol:         Study A
SAS Version:      ???
Developer:        Richann Watson 
Date:             2004 
Purpose:          
Operating Sys:    ???
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
%macro domixed(indsn=_LAST_ ,          /* Data set which contains the variables you wish to analyze. */
               y= ,                    /* Dependent variable in the model. */
               x= ,                    /* Fixed effects in the model */
               class= ,                /* Class variables in the model (e.g. treat site) */
               lsmeans= ,              /* Variable that the least squares mean and standard error needs */
                                       /* to be determined for (should be in the model) this is also the*/
                                       /* variables that the mean and standard deviation should be calc */
                                       /* The differences between groups as well as the confidence      */
                                       /* intervals will be calculated (optional)                       */
                                       /* NOTE: if this is not specified lsmeans, standard error, mean  */
                                       /* and standard deviation will NOT be calculated                 */
               sstype=3,               /* type of sum of square (e.g. hypte 1 (TESTS1); htype 2 (TESTS2); htype 3 (TESTS3)) */
               byvar= ,                /* number of analyses that are to be performed (optional) */
               alpha=.05,              /* Level of confidence used to determine the confidence intervals */
               random= ,               /* Random effects in the model (optional) */
               estimates= ,            /* specific estimate statements that the user wants to calculated (optional) */
               contrasts= ,            /* specific contrast statements that the user wants to calculated (optional) */
               cimnform=6.2,           /* format for the mean & confidence interval in the diffs1 dataset default to 6.2 */
               stdform=7.3,            /* format for the standard error in the diffs1 dataset default to 7.3 */
               transpose = Y           /* transpose the allmeans and the diffs1 datasets so that all the groups are in one record */
                                       /* (e.g. 4 treatments all 4 treatment means are in one record, all 4 treatment stderr are  */
                                       /* in one record, etc.) default to Y. Transposes the fitstatistics so all are on one record*/
);

   /* using proc mixed to get the least square means and standard error, */
   /* confidence intervals and p-values for the model specified */

   /* use ods to generate temporary datasets */
   /* create datasets that have p-values, confidence intervals and lsmeans to be used later */
   /* this will only be created if the user request that they are created */
   ods output fitstatistics = fitstats;
   ods output tests&sstype = tests&sstype;
 
   /******************************NEED TO ADD A CONDITION TO LOOK FOR EITHER '(' OR '*'******************************/
   /******************************IF THIS IS IN THE X VARIABLE THEN THE SOLUTIONF DS   ******************************/
   /******************************WILL NOT BE CREATED	******************************/
   /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO DETERMINE WHAT DATA SETS ARE TO BE GENERATED !!!!!!!!!!!!!!!!!!!!!****/
   ods output solutionf = solutionf;
   %if &random ne %then %do;
      ods output solutionr = solutionr;
   %end;
   %if &lsmeans ne %then %do; 
      ods output lsmeans = lsmeans; 
      ods output diffs = diffs;
   %end;
   %if &contrasts ne %then %do;
      ods output contrasts = contrasts;
   %end;
   %if &estimates ne %then %do;
      ods output estimates = estimates;
   %end;
   /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO DETERMINE WHAT DATA SETS ARE TO BE GENERATED !!!!!!!!!!!!!!!!!!!!!****/

   %if &byvar ne %then %do;
      proc sort data=&indsn;
         by &byvar;
      run;
   %end;

   /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO GENERATE THE DATA SETS !!!!!!!!!!!!!!!!!!!!!****/
   proc mixed data=&indsn;
      %if &class ne %then %do;
         class &class;
      %end;

      /* if random is specified then need to use the new class variable */
      /* random statement if the random effect is specified */
      /* this will treat the specified variable as a random */
      /* variable as well as create the estimates */
      %if &random ne %then %do;
         /* need to determine if the type of sum of squares probabilities are to be calculated */
         /* htype=3 says that we want type III sum squares probabilities */
         /* htype=2 says that we want type II sum squares probabilities */
         /* htype=1 says that we want type I sum squares probabilities  */
         model &y = &x / htype=&sstype solution;
         random &random / solution;
      %end;
      %else %do;
         model &y = &x / htype=&sstype solution;
      %end;

      %if &byvar ne %then %do;
         by &byvar;
      %end;

      /* get the least square means, standard error and p-values only if a variable is specified */
      /* also creates the estimates, standard error and p-value for the differences */
      /* it also creates the alpha level confidence intervals for the lsmeans and differences */
      %if &lsmeans ne %then %do;
         lsmeans &lsmeans / diff cl alpha=&alpha;
      %end;

      /* creates the estimates and standard error for the user specified estimate statement(s) */
      &estimates;

      /* creates the contrasts for the user specified contrast statement(s) */
      &contrasts;
   run;
   /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO GENERATE THE DATA SETS !!!!!!!!!!!!!!!!!!!!!****/
 
   /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO CALCULATE THE OBSERVED MEANS AND THE STANDARD DEVIATION !!!!!!!!!!!!!!!!!!!!!****/
   /* if the lsmean and mean are calculated then they need to be combined into one dataset */
   %if &lsmeans ne %then %do;
      /* using proc means to get the observed mean change and standard error for each fixed effect */
      proc means data=&indsn;
         class &lsmeans;
         var &y;
         %if &byvar ne %then %do;
            by &byvar;
         %end;
         output out=means mean=obs_mean std=obs_std;
         ways 1; /* this does NOT allow for all conditional means -- does each unconditionally/independently */
      run;
      /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO CALCULATE THE OBSERVED MEANS AND THE STANDARD DEVIATION !!!!!!!!!!!!!!!!!!!!!****/

      /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO CREATE THE ALLMEANS DATA SET !!!!!!!!!!!!!!!!!!!!!****/
      /* determine the number of variables that the lsmeans/means are being calculated for */
      %let i = 1;
      %do %while(%scan(&lsmeans, &i) ne);
         %let i = %eval(&i + 1);
      %end;
      %let numlsmeans = %eval(&i - 1);

      proc sort data=means;
         by &lsmeans;
      run;

      %let gvars=;
      %do i = 1 %to &numlsmeans;
         %let gvars = &gvars a.&i;
      %end;

      data _null_;
         set &indsn;
         array ls {*} &lsmeans;
         %let temp = &lsmeans ;
         %do i = 1 %to &numlsmeans;
            call symput("a&i", vformat(ls{&i}) ); /* determine the format of the lsmeans variables in the original data set */
            %let z&i = %scan(&temp,&i); /* create macro variables that contain the lsmeans variables */
         %end;
      run;

      /* redefine the lsmeans variable lengths based on what was in the original data set */
      data lsmeans;
         set lsmeans;
         %do k = 1 %to &numlsmeans;
            format &&&z&k &&&a&k;
         %end;
      run;

      /* if the data type is numeric then we need to redefine the */
      /* missing values from ._ to . so that it will merge with the */
      /* means data set */
      data lsmeans;
         set lsmeans;
         array ls {*} &lsmeans;
         array x {*} $ x1 - x&numlsmeans;
         do j = 1 to &numlsmeans;
            x{j} = vtype(ls{j});   /* this will determine what the data type for each variable is */
            if x{j} = 'N' and ls{j} = ._ then ls{j} = .; 
            if x{j} = 'C' then ls{j} = left(trim(ls{j})); 
         end;
      run;

      proc sort data=lsmeans;
         by &lsmeans;
      run;
 
      /* redefine the lsmeans variable lengths based on what was in the original data set */
      data means;
         set means;
         %do k = 1 %to &numlsmeans;
            format &&&z&k &&&a&k;
         %end;
      run;

      /* if the data type is numeric then we need to redefine the */
      /* missing values from ._ to . so that it will merge with the */
      /* means data set */
      data means;
         set means;
         array ls {*} &lsmeans;
         array x {*} $ x1 - x&numlsmeans;
         do j = 1 to &numlsmeans;
            x{j} = vtype(ls{j});   /* this will determine what the data type for each variable is */
            if x{j} = 'N' and ls{j} = ._ then ls{j} = .; 
            if x{j} = 'C' then ls{j} = left(trim(ls{j})); 
         end;
      run;

      proc sort data=means;
         by &lsmeans;
      run;

      /* combine the lsmeans data with the observed means data */
      data allmeans;
         merge lsmeans means;
         format obs_mean estimate &cimnform obs_std stderr &stdform;
         by &lsmeans &byvar;
         rename estimate = lsm_est stderr = lsm_std;
      run;
      /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO CREATE THE ALLMEANS DATA SET !!!!!!!!!!!!!!!!!!!!!****/

      /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO CREATE THE DIFFS1 DATA SET !!!!!!!!!!!!!!!!!!!!!****/
      /* need to create an array for the lsmean variables for the diffs */
      /* in the diffs dataset the variables that are being compared are */
      /* distinguished with the original variable name and the variable */
      /* name with an "_" (i.e. newtreat and _newtreat) -- need to	*/
      /* create the "_" variables */
      proc sort data=diffs out=temp nodupkey;
         by effect;
      run;

      data _null_; set temp; retain _vars;
         length _vars $40.;
         _vars = compress(_vars) || " _" || effect;
         put "vars =" _vars;
         call symput('_lsmeans', _vars);
      run;
 
      /* create a confidence interval (combine lower and upper) */
      /* create a mean and standard error variable */
      data diffs1;
         set diffs;
         array vars {*} &lsmeans; 
         array _vars {*} &_lsmeans; 
         length label ci est_std $30.; 
         format probt 7.3;
         do i = 1 to dim(vars);
            if vars{i} ne . then do;
               label = compress(vars{i})|| ' vs. ' || compress(_vars{i});
               ci = compress(put(lower, &cimnform)) || ' - ' || compress(put(upper, &cimnform));
               est_std = compress(put(estimate, &cimnform)) || ' (' || compress(put(stderr, &stdform)) || ')';
               output;
            end; 
         end; 
      run;

      /* get rid of miscellaneous records */
      data diffs1;
         set diffs1;
         if label ne '_ vs. _';
      run;
      /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO CREATE THE DIFFS1 DATA SET !!!!!!!!!!!!!!!!!!!!!****/
   %end;

   /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO DETERMINE IF ANY OF THE DATA SETS SHOULD BE TRANSPOSED !!!!!!!!!!!!!!!!!!!!!****/
   /* transpose the data so that all the treat lsmeans are on one record, */
   /* all the stderr are on one record, all the observed means are on one */
   /* record, all the standard deviations are on one record, all the ci */
   /* for diffs are on one record, all the diffs mean and stderr are on */
   /* one record -- makes for easier treatment to treatment comparison */
   /* also always for printing treatments across rather than down a page */
   %if &transpose = Y %then %do;

      /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO TRANSPOSE THE MEANS AND STD/ERR TO CREATE ALLMEANST !!!!!!!!!!!!!!!!!!!!!****/
      %if &lsmeans ne %then %do;
         %if &byvar ne %then %do; 
            proc sort data=allmeans; 
               by &byvar;
            run;
         %end;

         /* make the estimate/mean and the standard deviation/error */
         /* into character variables so that they keep the format */
         /* when they are transposed */
         data allmeans;
            set allmeans;
            length lsm_est_ lsm_std_ obs_mean_ obs_std_ $20.; 
            lsm_est_ = left(trim(put(lsm_est, &cimnform))); 
            lsm_std_ = left(trim(put(lsm_std, &stdform))); 
            obs_mean_ = left(trim(put(obs_mean, &cimnform))); 
            obs_std_ = left(trim(put(obs_std, &stdform)));
         run;

         proc sort data=allmeans;
            by effect &byvar;
         run;

         /* transpose the data so that all the obs means, ls means, all std and all ste are on individual records for each effect */
         proc transpose data=allmeans out=allmeanst; 
            var lsm_est_ lsm_std_ obs_mean_ obs_std_; 
            by effect &byvar;
         run;
 
         /* create a label and an index variable that will be used to merge the p-value in */
         data allmeanst; 
            set allmeanst; 
            length label $20.;
            if _NAME_ = 'obs_mean_' then label = 'Observed Mean'; 
            if _NAME_ = 'obs_std_' then label = 'Standard Deviation'; 
            if _NAME_ = 'lsm_est_' then label = 'Least Square Mean'; 
            if _NAME_ = 'lsm_std_' then label = 'Standard Error'; 
            index = 1;
         run;
         /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO TRANSPOSE THE MEANS AND STD/ERR TO CREATE ALLMEANST !!!!!!!!!!!!!!!!!!!!!****/

         /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO TRANSPOSE THE EST & C.I. FOR EFFECT DIFF TO CREATE DIFFST !!!!!!!!!!!!!!!!!!!!!****/
         proc sort data=diffs1;
            by effect &byvar;
         run;

         proc transpose data=diffs1 out=diffst prefix = label;
            var ci est_std probt;
            id label;
            by effect &byvar;
         run;

         data diffst;
            set diffst;
            length label $30.;
            if _NAME_ = 'label' then label = 'Label';
            if _NAME_ = 'ci' then label = 'Confidence Interval';
            if _NAME_ = 'est_std' then label = 'Estimate (Std. Error)';
            if _NAME_ = 'Probt' then label = 'P-Value';
            drop _NAME_ _LABEL_;
         run;
      %end;
      /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO TRANSPOSE THE EST & C.I. FOR EFFECT DIFF TO CREATE DIFFST !!!!!!!!!!!!!!!!!!!!!****/

      /****!!!!!!!!!!!!!!!!!!!!! BEGIN SECTION TO TRANSPOSE THE FIT STATISTICS TO CREATE FITSTATT !!!!!!!!!!!!!!!!!!!!!****/
      %if &byvar ne %then %do;
         proc sort data=fitstats;
            by &byvar;
         run;
      %end;

      proc transpose data=fitstats out=fitstatt;
            var value;
            id descr;
            %if &byvar ne %then %do;
               by &byvar;
            %end;
      run;
      /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO TRANSPOSE THE FIT STATISTICS TO CREATE FITSTATT !!!!!!!!!!!!!!!!!!!!!****/
   %end;
   /****!!!!!!!!!!!!!!!!!!!!! END SECTION TO DETERMINE IF ANY OF THE DATA SETS SHOULD BE TRANSPOSED !!!!!!!!!!!!!!!!!!!!!****/

%mend;
