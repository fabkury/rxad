%LET _CLIENTTASKLABEL='Drug use strings';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\rxad\rxad.egp';
%LET _CLIENTPROJECTNAME='rxad.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 10000;
%let drop_tables = 1;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let proj_cn = RXAD;
%let table_list = CCBLKR DIURTC RAS STATIN PPI BBLKR;
%let study_start = MDY(1, 1, 2007);
%let study_end = MDY(12, 31, 2015);
%let regression_intervals = WEEK SEMIMONTH MONTH; /* Arguments to intck() */
%let build_tag = _K;
%let make_continuous_string = 1;


%macro make_drug_string_week(input, output, interval);
%let claim_end = MIN(intnx('day', SRVC_DT, DAYS_SUPLY_NUM-1), &study_end);

data &output;
	set &input (keep = BENE_ID SRVC_DT DAYS_SUPLY_NUM);
	by BENE_ID;
	retain BINARY_STRING CONTINUOUS_STRING;

	/* TO DO: Discuss this with Seo Baik. */
	if DAYS_SUPLY_NUM = 0 then DAYS_SUPLY_NUM = 1;

	TEMP_BINARY_STRING = repeat('0', intck('week', &study_start, SRVC_DT)-1)
		|| repeat('1', intck('week', SRVC_DT, &claim_end))
		|| repeat('0', intck('week', &claim_end, &study_end)-1);

	if intck('week', SRVC_DT, &claim_end) > 0 then
		/* The prescription crosses the boundary of a week, therefore 2 or 3 numbers
		will represent it. The middle number -- the 7s -- will be automatically
		excluded if the length provided to repeat() is negative. */
		TEMP_CONT_STRING = repeat('0', intck('week', &study_start, SRVC_DT)-1)
			|| put(intck('day', SRVC_DT, intnx('week', SRVC_DT, 0, 'end'))+1, z1.)
			|| repeat('7', intck('week', SRVC_DT, &claim_end)-2)
			|| put(intck('day', intnx('week', &claim_end, 0, 'beg'), &claim_end)+1, z1.)
			|| repeat('0', intck('week', &claim_end, &study_end)-1);
	else
		/* The prescription does not cross the boundary of a week, therefore a single number
		will represent it. */
		TEMP_CONT_STRING = repeat('0', intck('week', &study_start, SRVC_DT)-1)
			|| put(intck('day', SRVC_DT, &claim_end)+1, z1.)
			|| repeat('0', intck('week', &claim_end, &study_end)-1);

	if first.BENE_ID then do;
		/* Store the string of the first row. */
		BINARY_STRING = TEMP_BINARY_STRING;
		CONTINUOUS_STRING = TEMP_CONT_STRING;
	end;
	else do i = 1 to length(BINARY_STRING);
		/* Add the strings across rows. */
		if substr(TEMP_BINARY_STRING, i, 1) = '1' then substr(BINARY_STRING, i, 1) = '1';
		substr(CONTINUOUS_STRING, i, 1) = put(min(input(substr(CONTINUOUS_STRING, i, 1), 1.)
			+ input(substr(TEMP_CONT_STRING, i, 1), 1.), 7), z.);
	end;
	
	if last.BENE_ID then do;
		/* Remove temporary data and output a single row per beneficiary. */
		drop i TEMP_BINARY_STRING TEMP_CONT_STRING SRVC_DT DAYS_SUPLY_NUM;
		output;
	end;

	%if &debug_mode %then if BENE_ID >= &debug_limit then stop;;
run;

proc sql;
select "&output" as Table,
	min(length(BINARY_STRING)) as min_binary, max(length(BINARY_STRING)) as max_binary,
	min(length(CONTINUOUS_STRING)) as min_continuous, max(length(CONTINUOUS_STRING)) as max_continuous
from &output;
quit;
%mend;

%macro make_drug_string_any(input, output, interval_name);
%let interval = "&interval_name";
%let binary_val = BINARY_&interval_name;
%let cont_val = CONTINUOUS_&interval_name;
%let claim_end = MIN(intnx('day', SRVC_DT, DAYS_SUPLY_NUM-1), &study_end);
%if &interval_name=QUARTER %then %let max_val = 90;
%if &interval_name=MONTH %then %let max_val = 30;
%if &interval_name=SEMIMONTH %then %let max_val = 15;
%if &interval_name=WEEK %then %let max_val = 7;

proc sql noprint;
select distinct
	intck(&interval, &study_start, &study_end)+1
	into: binary_intervals
from SH026250.cisa2_tab1_pp; /* Can be any table... */

select distinct
	(intck(&interval, &study_start, &study_end)+1)*3
	into: continuous_intervals
from SH026250.cisa2_tab1_pp; /* Can be any table... */
quit;

data &output;
	set &input (keep = BENE_ID SRVC_DT DAYS_SUPLY_NUM);
	by BENE_ID;
	retain &binary_val %if &make_continuous_string %then &cont_val; ;
	length &binary_val $ &binary_intervals;
	length TEMP_&binary_val $ &binary_intervals;
	%if &make_continuous_string %then %do;
	length &cont_val $ &continuous_intervals;
	length TEMP_&cont_val $ &continuous_intervals;
	%end;

	/* TO DO: Discuss this with Seo Baik. */
	if DAYS_SUPLY_NUM = 0 then DAYS_SUPLY_NUM = 1;

	/* TO DO: Use inline ternary operator (or equivalent) instead of these repetitive nested ifs. */
	if intck(&interval, &study_start, SRVC_DT) > 0 then
	do;
		if intck(&interval, &claim_end, &study_end) > 0 then
			TEMP_&binary_val = repeat('0', intck(&interval, &study_start, SRVC_DT)-1)
				|| repeat('1', intck(&interval, SRVC_DT, &claim_end))
				|| repeat('0', intck(&interval, &claim_end, &study_end)-1);
		else
			TEMP_&binary_val = repeat('0', intck(&interval, &study_start, SRVC_DT)-1)
				|| repeat('1', intck(&interval, SRVC_DT, &claim_end));
	end;
	else do;
		if intck(&interval, &claim_end, &study_end) > 0 then
			TEMP_&binary_val = repeat('1', intck(&interval, SRVC_DT, &claim_end))
				|| repeat('0', intck(&interval, &claim_end, &study_end)-1);
		else
			TEMP_&binary_val = repeat('1', intck(&interval, SRVC_DT, &claim_end));
	end;

	/* TO DO: The continuous string in this function is not working. */
	%if &make_continuous_string %then %do;
		if intck(&interval, SRVC_DT, &claim_end) > 0 then
			/* The prescription crosses the boundary of a week, therefore 2 or 3 numbers
			will represent it. The middle number -- the 7s -- will be automatically
			excluded if the length provided to repeat() is negative. */
			TEMP_&cont_val = repeat('00-', intck(&interval, &study_start, SRVC_DT)-1)
				|| put(intck('day', SRVC_DT, intnx(&interval, SRVC_DT, 0, 'end'))+1, z2.) || '-'
				|| repeat(put(&max_val, z2.)||'-', intck(&interval, SRVC_DT, &claim_end)-2)
				|| put(intck('day', intnx(&interval, &claim_end, 0, 'beg'), &claim_end)+1, z2.) || '-'
				|| repeat('00-', intck(&interval, &claim_end, &study_end)-1);
		else
			/* The prescription does not cross the boundary of an interval, therefore a single number
			will represent it. */
			TEMP_&cont_val = repeat('00-', intck(&interval, &study_start, SRVC_DT)-1)
				|| put(intck('day', SRVC_DT, &claim_end)+1, z2.) || '-'
				|| repeat('00-', intck(&interval, &claim_end, &study_end)-1);
	%end;

	if first.BENE_ID then do;
		/* Store the string of the first row. */
		&binary_val = TEMP_&binary_val;
		%if &make_continuous_string
			%then &cont_val = TEMP_&cont_val; ;
	end;
	else do i = 1 to &binary_intervals;
		/* Add the strings across rows. */
		if substr(TEMP_&binary_val, i, 1) = '1'
			then substr(&binary_val, i, 1) = '1';
		%if &make_continuous_string %then
			substr(&cont_val, (i*3)-2, 2) =
				put(min(input(substr(&cont_val, (i*3)-2, 2), 2.)
				+ input(substr(TEMP_&cont_val, (i*3)-2, 2), 2.),
				&max_val), z2.);;
	end;
	
	if last.BENE_ID then do;
		/* Remove temporary data and output a single row per beneficiary. */
		drop i TEMP_&binary_val SRVC_DT DAYS_SUPLY_NUM
			%if &make_continuous_string %then TEMP_&cont_val; ;
		output;
	end;

	%if &debug_mode %then if BENE_ID >= &debug_limit then stop;;
run;

proc sql;
select "&output" as Table,
	min(length(&binary_val)) as min_binary,
	max(length(&binary_val)) as max_binary
	%if &make_continuous_string %then ,
		min(length(&cont_val)) as min_continuous,
		max(length(&cont_val)) as max_continuous;
from &output;
quit;
%mend;

%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

%do t=1 %to %sysfunc(countw(&table_list));
	%let tbl = %sysfunc(scan(&table_list, &t));
	%do IL=1 %to %sysfunc(countw(&regression_intervals));
		%let ri = %sysfunc(scan(&regression_intervals, &IL));
		%make_drug_string_any(&sharedlib..&proj_cn._&tbl._CLMS,
			&sharedlib..&proj_cn._&tbl._STR_&ri.&build_tag.&di, &ri);
	%end;

	data &sharedlib..&proj_cn._&tbl._STR&build_tag.&di;
		merge
			%do IL=1 %to %sysfunc(countw(&regression_intervals));
				%let ri = %sysfunc(scan(&regression_intervals, &IL));
				&sharedlib..&proj_cn._&tbl._STR_&ri.&build_tag.&di
			%end;;
	run;

	%if &drop_tables %then %do;
		proc sql;
		%do IL=1 %to %sysfunc(countw(&regression_intervals));
			%let ri = %sysfunc(scan(&regression_intervals, &IL));
			drop table &sharedlib..&proj_cn._&tbl._STR_&ri.&build_tag.&di;
		%end;
		quit;
	%end;
%end;
%mend;

%make_tables;

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

