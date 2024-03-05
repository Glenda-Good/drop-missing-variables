/**************************************************************
*the purpose of this program is to drop variables with
*missing values from a SAS dataset.
*This code is designed to have a similar function to
*The DROPMISS macro of Selvaratname Sridharma
*see "Dropping Automatically Variables with Only Missing Values"
*		SAS Global Forum 2010
*But the DROPMISS macro fails sometimes, so this is an alternative
*Note: this program may be slower with datasets with large numbers of character variables
*		it was tested on NYS ACS data with about 50 character variables and 30,000 numeric variables
*programmed by Gwen LaSelva
*inputs: 
	library name 
	name of input SAS dataset
	name of output SAS dataset
	alternative missing value for numeric variables, for example -1 or 999999

*outputs: SAS dataset*
*03/07/2016, find that this will bomb if no numeric variables
*   so modify code to deliberately add a variable called -extravariable- which will be dropped later
*   does not seem elegant, but works
*see: https://www.lexjansen.com/nesug/nesug13/90_Final_Paper.pdf
*******************************************************************/
/*specify any libraries used*/

libname pl 'M:\ARCGIS\Demographics\Census\2020\DHC\saswork\bygeo';
libname pl2 'M:\ARCGIS\Demographics\Census\2020\DHC\SAS';

/*specify the input and output datasets*/

%let dsin=pl.dhc2020_ZCTA;
%let dsout=pl2.dhc2020_ZCTA;

/*specify an alternative missing value for numeric variables.
this value should be a number*/
%let altnumericmissvalue=-1; /*for Census margins of error, use negative one*/


/*shouldn't need to modify below this line*/
/*STEP 1: PREPARATION*/
/*get the label and compression of the input dataset and put them into a macro variables,
use them at the end so the new dataset has the same label and compression as
the original*/
data _null_;
temptime=put(time(),hhmm5.);
putlog "start time=" temptime;
run;
proc contents data=&dsin noprint out=mycontents (keep=memlabel compress);
run;
data _null_;
set mycontents(obs=1);
call symputx("mylabel",memlabel);
call symputx("mycompress",compress);
run;
/*first, make output dataset to work with, so we don't accidentally mess
up the original dataset if something goes wrong*/
data &dsout (compress=&mycompress.);
/*create an additional variable to avoid errors if there are no numeric variables, should be deleted later*/
retain extravariable (&altnumericmissvalue.);
set &dsin;
run;

/*STEP 2: FIND ALL NUMERIC VARIABLES WITH ALL MISSING VALUES*/
/*proc means with the N statistic should count number of non-missing values for numeric variables*/
proc means data=&dsout noprint;
output out=checknumeric(drop=_:) n=;/*get the number of NON-MISSING for all numeric variables*/
run; /*one observation, many variables.  Takes just over 1 minute for the example dataset*/

run;
proc transpose data=checknumeric out=checknumeric2 (drop=_label_ rename=(col1=numhere _name_=vname));
run;
data dropnumeric;
set checknumeric2 (where=(numhere=0));
run;

run;
/*Use PROC FREQ to get character variables whose values are all missing
it is slower than PROC MEANS*/
ods output NLevels=checkchar;
ods html close; /*suppress default output, because we only want a dataset*/
/*for older versions of SAS, use ods listing close;*/
proc freq data=&dsout nlevels;
tables _char_ /noprint;
run;
ods html;
ods output close;
*proc print data=checkchar(obs=10);run;
data dropchar (rename=(TableVar=vname));
set checkchar (where=(NNonMissLevels=0));
run;
/*You could use proc freq for all of the variables, but it would be slow*/


/*now, find out if any of the variables contain only the alternative missing value*/
/*let us assume that if the minimum and maximum values are both equal to
the alternative missing value, the variable should be dropped*/
proc means data=&dsout noprint;
output out=biggest(drop=_:) max=;
run;
proc means data=&dsout noprint;
output out=smallest(drop=_:) min=;
run;

proc transpose data=biggest out=biggest2 (drop=_label_ rename=(col1=greatest _name_=vname));
run;
proc transpose data=smallest out=smallest2 (drop=_label_ rename=(col1=least _name_=vname));
run;
proc sort data=biggest2; by vname; run; 
proc sort data=smallest2; by vname; run;
data dropnumericalt;
merge biggest2 smallest2;
by vname;
if least=&altnumericmissvalue. and greatest=&altnumericmissvalue. then output;
run;


/*STEP 3: COMBINE LISTS OF CHARACTER AND NUMERIC VARIABLES TO DROP*/
/*for convience, combine the lists of character and numeric variables to drop*/
data allvarstodrop;
format vname $32.; /*maximum length of SAS variable name.  Use this statement to make sure the names are not truncated*/
set dropchar(keep=vname) dropnumeric (drop=numhere) dropnumericalt (drop=greatest least) ;
varsize=length(vname)+1;
run;


/*STEP 4: DROP THE VARIABLES*/
/* create a character variable containing the list of variables
to be dropped.  A character variable can be up to 32767 characters,
and can therefore hold a list of at least 992 SAS variables, maybe more*/
/*if the sum of varsize is more than 32767 need to create additional
observations in the dataset to hold the additional variables*/
data varstodroplist (keep=varlist varsizesum);
format varlist $32767.; /*this is the maximum size of a character variable*/
retain varsizesum varlist;
set allvarstodrop end=eof;
varsizesum=sum(of varsize varsizesum);
if varsizesum>32767 then do;
	output;
	putlog vname varsizesum;
	varsizesum=varsize; varlist=vname; /*reset*/
end;
else varlist=catx(' ',varlist,vname);
if eof=1 then output;
run;

/*use call execute to repeat the dropping for each set of variable names*/
data _null_;
set varstodroplist;
call execute("data &dsout(label='&mylabel' compress=&mycompress.);");
call execute("set &dsout(drop=");
call execute(varlist);
call execute(");");
call execute("run;");
run;

data _null_;
temptime=put(time(),hhmm5.);
putlog "end time=" temptime;
run;



