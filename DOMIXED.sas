libname adam 'C:\Users\gonza\Desktop\GTL_Book_with_Kriss_Harris\Example Code and Data\Data\Chapter 3';

data newvital;
set adam.advs;
where ady > 1 and paramcd = 'SYSBP';
x = ranuni(3415);
if x <= .25 then TREAT = 1;
else if x <= .5 then TREAT = 2;
else if x <= .75 then TREAT = 3;
else TREAT = 4;

keep USUBJID SITEID TRTPN TREAT CHG BASE ADY x;
rename CHG = CHGSYS BASE = BASESYS SITEID = SITEGRP;
run;

proc sort data = vs;
   by TREAT;
run;

%domixed(indsn = newvital, y = CHGSYS, x = TREAT SITEGRP BASESYS, 
         class = TREAT SITEGRP, lsmeans = TREAT, CIMNFORM = 5.2, STDFORM = 5.3,  
         estimates = %str(estimate '1 vs 2, 3, 4' TREAT 1 -.33 -.33 -.34 / cl;
                          estimate '2 vs 1, 3, 4' TREAT -.33 1 -.33 -.34 / cl;
                          estimate '3 vs 1, 2, 4' TREAT -.33 -.33 1 -.34 / cl;
                          estimate '4 vs 1, 2, 3' TREAT -.33 -.33 -.33 1 / cl;))